# frozen_string_literal: true

require "test_helper"
require_relative "../../../../config/instrumentation/job"

# Copied from https://github.com/github/github/blob/4299045245cd2ae587bac0b5557c6052fbe8819c/test/lib/github/config/instrumentation/failbot_test.rb#L7
class FailbotInstrumentationTest < ActionDispatch::IntegrationTest
  test "report.failbot success" do
    payload = {
      "app" => "advisory-db",
      "report_status" => "success",
      "elapsed_ms" => 123.456,
      "payload_size" => 7481,
    }

    AdvisoryDB.stats.expects(:distribution).with("failbot.report", 123.456, tags: ["application:advisory-db", "status:success"])
    ActiveSupport::Notifications.instrument("report.failbot", payload)
  end

  test "report.failbot failure" do
    payload = {
      "app" => "advisory-db",
      "report_status" => "error",
      "elapsed_ms" => 654.321,
      "exception_type" => "RuntimeError",
      "payload_size" => 7481,
    }

    AdvisoryDB.stats.expects(:distribution).with("failbot.report", 654.321, tags: ["application:advisory-db", "status:error", "exception:RuntimeError"])
    ActiveSupport::Notifications.instrument("report.failbot", payload)
  end
end
