# frozen_string_literal: true

require "pry"
require "webmock/rspec"

require "licensify"
require "support/twirp_test_helpers"

RSpec.configure do |config|
  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
