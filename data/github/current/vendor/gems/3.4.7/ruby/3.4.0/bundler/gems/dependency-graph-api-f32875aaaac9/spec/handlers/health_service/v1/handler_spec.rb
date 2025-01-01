require "rails_helper"

describe HealthService::V1::Handler do
  let(:handler) { HealthService::V1::Handler.new }

  describe "health service functionality" do
    it "ping works" do
      req = DependencyGraphAPI::V1::PingRequest.new


      response = handler.ping(req, {})

      expect(response[:response]).to eq("Pong!")
    end

    it "boom works" do
      req = DependencyGraphAPI::V1::BoomRequest.new

      response = handler.boom(req, {})

      expect(response.code).to eq(:internal)
    end
  end
end
