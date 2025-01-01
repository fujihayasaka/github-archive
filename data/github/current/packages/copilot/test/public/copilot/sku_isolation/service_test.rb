# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotSKUIsolationServiceTest < GitHub::TestCase
  context "#host" do
    test "returns the host" do
      service = Copilot::SKUIsolation::Service.new do
        "example.com"
      end

      assert_equal "example.com", service.host
    end
  end

  context "#endpoint" do
    test "builds an HTTPS endpoint from the host" do
      service = Copilot::SKUIsolation::Service.new do
        "example.com"
      end

      assert_equal "https://example.com", service.endpoint
    end

    test "raises an error if the host is not set properly" do
      service = Copilot::SKUIsolation::Service.new do
        ""
      end

      assert_raises URI::Error do
        service.endpoint
      end
    end
  end
end
