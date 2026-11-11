# frozen_string_literal: true

require "rails_helper"
require "chatops/controller/rspec"

RSpec.describe ChatopsController, :cloud do
  include_context "chatops controller"

  describe "validate config file" do
    subject(:run_chatop) do
      chat "dependabot validate config file #{repo.full_name}", "user", "#dependabot-ops"
    end

    let(:repo) { create(:repo) }

    let(:config_file) do
      OpenStruct.new(path: ".github/dependabot.yml", content: config_file_body)
    end

    let(:dummy_config_file_fetcher) do
      instance_double(FetchConfigFile, run: config_file)
    end

    let(:json_header) { { "Content-Type" => "application/json" } }
    let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }

    before do
      allow(FetchConfigFile).
        to receive(:new).
        and_return(dummy_config_file_fetcher)
      allow(GitHubHelpers).to receive(:installation_access_token_for)
    end

    context "when the config file is valid" do
      let(:config_file_body) { fixture("config_files/minimal.yml") }

      it "returns a success message" do
        run_chatop

        expect(chatop_response).to include("looks valid")
      end
    end

    context "when the config file is invalid" do
      let(:config_file_body) { fixture("config_files/missing_required_key.yml") }

      it "returns a failure message" do
        run_chatop

        expect(chatop_response).to include("Found the following configuration issues")
      end
    end
  end
end
