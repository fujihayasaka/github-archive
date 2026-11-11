# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "minitest/autorun"

require "advisory_db_toolkit"
require "vcr"
require "webmock"
require "mocha/minitest"
require "support/tools/logger"
require "support/tools/http_client"

VCR.configure do |config|
  config.hook_into :webmock
  config.cassette_library_dir = "test/cassettes"
end

AdvisoryDBToolkit.logger = Tools::Logger.new
