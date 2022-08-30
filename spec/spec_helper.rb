$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))

require 'ostruct'
require 'debug'
require 'factory_girl'
require 'grape/middleware/lograge'

FactoryGirl.find_definitions

RSpec.configure do |config|
  config.raise_errors_for_deprecations!
  config.include FactoryGirl::Syntax::Methods
end
