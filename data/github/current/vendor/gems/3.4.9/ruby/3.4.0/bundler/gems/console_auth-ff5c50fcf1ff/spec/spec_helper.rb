# frozen_string_literal: true

require "console_auth"
require "webmock/rspec"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:context) do
    ENV['FAILBOT_BACKEND'] ||= 'memory'
    Failbot.setup(ENV, {:app => 'console_auth_tests'})
  end
end
