# frozen_string_literal: true

require "rails_helper"
require "chatops/controller/rspec"

RSpec.describe ChatopsController, :cloud do
  include ActiveSupport::Testing::TimeHelpers

  include_context "chatops controller"

  let(:env) { "stage" }
  let(:ecosystem) { "gomod" }
  let(:version) { "33ee174bc345b50bc6a15308f22a3e6432808e1c" }

  describe "ecosystem-versions" do
    subject(:run_chatop) do
      chat "dependabot ecosystem-versions #{env}", env, "#dependabot-ops"
    end

    it "outputs the ecosystem versions" do
      run_chatop

      expect(chatop_response).to eq("Environment stage ecosystem versions: \n```\n\n```")
    end

    context "when there's an entry" do
      before do
        FactoryBot.create(:updater_version, env: env, ecosystem: ecosystem, version: version)
        # not returned because the chat-op specifies staging as the query
        FactoryBot.create(:updater_version, env: "prod", ecosystem: ecosystem, version: "123")
      end

      it "outputs the entries" do
        run_chatop

        expect(chatop_response).to eq("Environment stage ecosystem versions: \n```\n" \
                                      "gomod: 33ee174bc345b50bc6a15308f22a3e6432808e1c\n```")
      end
    end
  end

  describe "set-ecosystem-version" do
    subject(:run_chatop) do
      chat "dependabot set-ecosystem-version #{env} #{ecosystem} #{chatop_version}", env, "#dependabot-ops"
    end

    let(:chatop_version) { version }

    before do
      stub_request(:get, "https://ghcr.io/token?scope=repository:dependabot/dependabot-updater-gomod:pull").
        to_return(status: 200, body: "{\"token\":\"ghcr_token\"}")

      stub_request(:head, "https://ghcr.io/v2/dependabot/dependabot-updater-gomod/manifests/33ee174bc345b50bc6a15308f22a3e6432808e1c").
        to_return(status: 200)
    end

    it "sets the ecosystem version" do
      run_chatop

      expect(chatop_response).to start_with(
        "Updated 'stage' updater version: `gomod/33ee174bc345b50bc6a15308f22a3e6432808e1c`"
      )
    end

    context "when there's an entry" do
      before do
        FactoryBot.create(:updater_version, env: env, ecosystem: ecosystem, version: version)
        # not returned because the chat-op specifies staging as the query
        FactoryBot.create(:updater_version, env: "prod", ecosystem: ecosystem, version: "123")

        stub_request(:get, "https://ghcr.io/token?scope=repository:dependabot/dependabot-updater-gomod:pull").
          to_return(status: 200, body: "{\"token\":\"ghcr_token\"}")

        stub_request(:head, "https://ghcr.io/v2/dependabot/dependabot-updater-gomod/manifests/123").
          to_return(status: 200)
      end

      let(:chatop_version) { "123" }

      it "outputs the previous entries" do
        run_chatop

        expect(chatop_response).to eq <<~CHATOP_OUTPUT
          Updated 'stage' updater version: `gomod/123`
          [Sentry](https://github.sentry.io/releases/#{chatop_version}/?project=1451818)

          Previous versions:
          ```
          33ee174bc345b50bc6a15308f22a3e6432808e1c: gomod
          ```
        CHATOP_OUTPUT
      end
    end

    context "when setting all ecosystems" do
      before do
        ParseConfigFile::PACKAGE_MANAGER_LOOKUP.each_key do |package_manager|
          stub_request(:get, "https://ghcr.io/token?scope=repository:dependabot/dependabot-updater-#{package_manager}:pull").
            to_return(status: 200, body: "{\"token\":\"ghcr_token\"}")

          stub_request(:head, "https://ghcr.io/v2/dependabot/dependabot-updater-#{package_manager}/manifests/456").
            to_return(status: 200)
        end
      end

      let(:chatop_version) { "456" }
      let(:ecosystem) { "*" }

      it "sets all verisons" do
        run_chatop

        expect(chatop_response).to start_with("Updated all 'stage' updater versions to: `456`")
        expect(UpdaterVersion.all.length).to eq(ParseConfigFile::PACKAGE_MANAGER_LOOKUP.length)
        expect(UpdaterVersion.all.all? { |uv| uv.version == "456" }).to eq(true)
      end

      context "and one image is not in GHCR" do
        before do
          url = "https://ghcr.io/v2/dependabot/dependabot-updater-pip/manifests/456"
          stub_request(:head, url).
            to_return(status: 404)
        end

        it "tells you which one is missing" do
          run_chatop

          expect(chatop_error).to eq("Updater `pip/456` not found in GHCR")
        end
      end
    end
  end
end
