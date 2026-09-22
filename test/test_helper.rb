ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

# No outbound HTTP in tests. Individual tests that need a local socket (for
# example the ShopinfoApi timeout tests) allow it explicitly.
WebMock.disable_net_connect!

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |f| require f }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Add more helper methods to be used by all tests here...
  end
end
