# frozen_string_literal: true

require "rails_helper"

RSpec.describe HealthService::V1::Handler do
  let(:service) do
    DependabotApi::V1::HealthService.new(described_class.new)
  end

  describe "ping" do
    it "returns a healthy message" do
      ping = service.call_rpc :Ping

      expect(ping.msg).to match(/^Healthy at/)
    end
  end
end
