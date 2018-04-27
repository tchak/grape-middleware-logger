require 'grape'
require 'lograge'
require 'lograge/formatters/rails_logger'

class Grape::Middleware::Lograge < Grape::Middleware::Globals
  BACKSLASH = '/'.freeze

  STATUS_CODE_TO_SYMBOL = Rack::Utils::SYMBOL_TO_STATUS_CODE.each_with_object({}) do |(symbol, status_code), hash|
    hash[status_code] = symbol
  end

  class << self
    attr_accessor :filter
  end

  def initialize(_, options = {})
    super
    @options[:filter] ||= self.class.filter
  end

  def before
    super

    @db_duration = 0

    @db_subscription = ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
      args[1] ||= Time.now # occasionally the start time is nil and will cause errors in Event
      event = ActiveSupport::Notifications::Event.new(*args)
      @db_duration += event.duration
    end if defined?(ActiveRecord)

    ActiveSupport::Notifications.instrument("start_processing.grape", raw_payload)
  end

  # @note Error and exception handling are required for the +after+ hooks
  #   Exceptions are logged as a 500 status and re-raised
  #   Other "errors" are caught, logged and re-thrown
  def call!(env)
    @env = env

    before

    ActiveSupport::Notifications.instrument("process_action.grape", raw_payload) do |payload|
      error = catch(:error) do
        begin
          @app_response = @app.call(@env)
        rescue => e
          after_exception(payload, e)
          raise e
        end

        nil
      end

      if error
        after_failure(payload, error)
        throw(:error, error)
      else
        after(payload, response.status)
      end

      @app_response
    end
  end

  def after(payload, status)
    payload[:status]     = status
    payload[:format]     = env['api.format']
    payload[:version]    = env['api.version']
    payload[:db_runtime] = @db_duration
  end

  def after_exception(payload, e)
    ActiveSupport::Notifications.unsubscribe(@db_subscription) if @db_subscription

    class_name = e.class.name
    status = e.respond_to?(:status) ? e.status : 500

    payload[:exception] = [class_name, e.message]
    payload[:backtrace] = e.backtrace

    unless ActionDispatch::ExceptionWrapper.rescue_responses[class_name].present?
      ActionDispatch::ExceptionWrapper.rescue_responses[class_name] = STATUS_CODE_TO_SYMBOL[status]
    end
  end

  def after_failure(payload, error)
    ActiveSupport::Notifications.unsubscribe(@db_subscription) if @db_subscription

    after(payload, error[:status])
  end

  def parameters
    request_params = env[Grape::Env::GRAPE_REQUEST_PARAMS].to_hash
    request_params.merge!(env['action_dispatch.request.request_parameters'.freeze] || {}) # for Rails
    if @options[:filter]
      @options[:filter].filter(request_params)
    else
      request_params
    end
  end

  def raw_payload
    {
      params:     parameters.merge(
        'action' => action_name.empty? ? 'index' : action_name,
        'controller' => controller
      ),
      method:     env[Grape::Env::GRAPE_REQUEST].request_method,
      path:       env[Grape::Env::GRAPE_REQUEST].path,
      user_agent: env['HTTP_USER_AGENT'],
      request_id: env['action_dispatch.request_id'],
      remote_ip:  env['action_dispatch.remote_ip'].to_s
    }
  end

  def endpoint
    env[Grape::Env::API_ENDPOINT]
  end

  def controller
    endpoint.options[:for].to_s
  end

  def action_name
    endpoint.options[:path].map { |path| path.to_s.sub(BACKSLASH, '') }.join(BACKSLASH)
  end
end

require_relative 'lograge/railtie' if defined?(Rails)
