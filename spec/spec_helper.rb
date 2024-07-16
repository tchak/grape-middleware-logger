$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))

require 'ostruct'
require 'factory_bot'
require 'grape/middleware/lograge'

FactoryBot.find_definitions

RSpec.configure do |config|
  config.raise_errors_for_deprecations!
  config.include FactoryBot::Syntax::Methods
end
