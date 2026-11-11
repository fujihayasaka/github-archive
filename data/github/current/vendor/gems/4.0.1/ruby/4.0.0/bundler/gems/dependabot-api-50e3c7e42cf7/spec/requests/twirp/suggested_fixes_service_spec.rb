# frozen_string_literal: true

require "twirp_helper"

RSpec.describe DependabotApi::V1::SuggestedFixesService,
               type: :request do
  include_context "internal twirp api"

  let(:start_time) { Time.now.utc }
  let(:end_time) { start_time + 1.second }

  before do
    allow(Failbot).to receive(:report)
    allow(MetricsClient).to receive(:timing)
    allow_any_instance_of(Services::RackApp).
      to receive(:time_now).and_return(start_time, end_time)
  end

  describe "GetSuggestedFix" do
    before do
      allow_any_instance_of(SuggestedFixesService::V1::Handler).
        to receive(:get_suggested_fix).
        and_return({ suggested_fix: { id: 1 } })

      rpc_call method: "GetSuggestedFix"
    end

    it "returns a 200" do
      expect(response.status).to be(200)
    end

    it "renders response" do
      msg = DependabotApi::V1::GetSuggestedFixResponse.
            decode(response.body)
      expect(msg.suggested_fix.id).to be(1)
    end
  end

  describe "ApplySuggestedFix" do
    before do
      allow_any_instance_of(SuggestedFixesService::V1::Handler).
        to receive(:apply_suggested_fix).
        and_return({ success: true })
      rpc_call method: "ApplySuggestedFix"
    end

    it "returns a 200" do
      expect(response.status).to be(200)
    end

    it "renders response" do
      msg = DependabotApi::V1::ApplySuggestedFixResponse.
            decode(response.body)
      expect(msg).not_to be_nil
    end
  end

  describe "DismissSuggestedFix" do
    before do
      allow_any_instance_of(SuggestedFixesService::V1::Handler).
        to receive(:dismiss_suggested_fix).
        and_return({ success: true })
      rpc_call method: "DismissSuggestedFix"
    end

    it "returns a 200" do
      expect(response.status).to be(200)
    end

    it "renders response" do
      msg = DependabotApi::V1::DismissSuggestedFixResponse.
            decode(response.body)
      expect(msg).not_to be_nil
    end
  end
end
