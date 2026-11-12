# frozen_string_literal: true

require "rails_helper"
require "github_helpers"

RSpec.describe GitHub::Twirp::GlobalId, :vcr do
  let(:github_api_url) do
    "http://host.docker.internal:3000/api/v3/"
  end

  let(:twirp_client) do
    GitHub::Twirp::Client.new(
      github_api_url: github_api_url.to_s,
      hmac_key: "dependabotapihmac"
    )
  end

  let(:global_id_api) do
    described_class.new(
      client: twirp_client
    )
  end

  context "get_github_next_global_id", :cloud do
    it "get next global for a repo" do
      expect(global_id_api.get_github_next_global_id("MDEwOlJlcG9zaXRvcnk0")).to eq("R_kgAE")
    end

    it "raises exception for empty globalId" do
      expect(MetricsClient).to receive(:increment).
        with("get_next_global_id.error")

      expect(Dependabot::Logger).to receive(:log_exception)

      expect { global_id_api.get_github_next_global_id("") }.
        to raise_error(GitHub::Twirp::GlobalId::GetGlobalIdError)
    end

    it "raises exception for an unparseable globalId" do
      expect(MetricsClient).to receive(:increment).
        with("get_next_global_id.error")

      expect(Dependabot::Logger).to receive(:log_exception)

      expect { global_id_api.get_github_next_global_id("non-parseable-id") }.
        to raise_error(GitHub::Twirp::GlobalId::GetGlobalIdError)
    end
  end

  context "on enterprise - get_next_global_id", :enterprise do
    it "returns the same input for enterprise scenarios" do
      expect(global_id_api.get_github_next_global_id("MDEwOlJlcG9zaXRvcnk0")).to eq("MDEwOlJlcG9zaXRvcnk0")
    end
  end
end
