# typed: true
# frozen_string_literal: true

require "connection_info"
require "test_helper"

class CanceledQueryReporterTest < GitHub::TestCase
  include GitHub::LoggerHelper

  context ".call" do
    test "does not emit log message when feature disabled" do
      unexpected_log = {
        "Body" => "canceled query",
      }
      refute_logged(**unexpected_log) do
        CanceledQueryReporter.call("SELECT /*+ MAX_EXECUTION_TIME(1000) */ SLEEP(10)")
      end
    end

    test "does not emit log message when enabled percentage is not parseable" do
      CanceledQueryReporter.stubs(:reporting_random_number).returns(1)

      unexpected_log = {
        "Body" => "canceled query",
      }
      refute_logged(**unexpected_log) do
        enable_environment_feature(percentage: "unparseable") do
          CanceledQueryReporter.call("SELECT /*+ MAX_EXECUTION_TIME(1000) */ SLEEP(10)")
        end
      end
    end

    test "does not emit log message when random number falls outside of enabled percentage" do
      CanceledQueryReporter.any_instance.stubs(:reporting_random_number).returns(51)

      unexpected_log = {
        "Body" => "canceled query",
      }
      refute_logged(**unexpected_log) do
        enable_environment_feature(percentage: 50) do
          CanceledQueryReporter.call("SELECT /*+ MAX_EXECUTION_TIME(1000) */ SLEEP(10)")
        end
      end
    end

    test "emits expected log message when random number falls within enabled percentage" do
      CanceledQueryReporter.any_instance.stubs(:reporting_random_number).returns(50)

      expected_log = {
        "Body" => "canceled query",
        "query_digest" => "SELECT SLEEP(?)",
      }
      assert_logged(**expected_log) do
        enable_environment_feature(percentage: 50) do
          CanceledQueryReporter.call("SELECT /*+ MAX_EXECUTION_TIME(1000) */ SLEEP(10)")
        end
      end
    end
  end

  def enable_environment_feature(percentage: 100)
    ENV["REPORT_CANCELED_QUERY_PERCENTAGE"] = percentage.to_s
    yield
  ensure
    ENV.delete("REPORT_CANCELED_QUERY_PERCENTAGE")
  end
end
