# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotSKUIsolationServiceTest < GitHub::TestCase
  [
    ["copilot.com", "copilot.com", "https://copilot.com"],
    ["https://copilot.com", "copilot.com", "https://copilot.com"],
    ["http://copilot.com", "copilot.com", "http://copilot.com"],
    ["http://localhost:1234", "localhost:1234", "http://localhost:1234"],
  ].each do |input, expected_host, expected_endpoint|
    context "#{input}" do
      test "returns the expected host" do
        service = Copilot::SKUIsolation::Service.new { input }
        assert_equal expected_host, service.host
      end

      test "returns the expected endpoint" do
        service = Copilot::SKUIsolation::Service.new { input }
        assert_equal expected_endpoint, service.endpoint
      end
    end
  end
end
