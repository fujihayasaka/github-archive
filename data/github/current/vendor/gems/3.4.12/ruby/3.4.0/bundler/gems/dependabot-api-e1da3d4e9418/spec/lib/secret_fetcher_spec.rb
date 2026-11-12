# frozen_string_literal: true

require "secret_fetcher"
require "rails_helper"

# To regenerate the cassettes for these tests:
# 1. Delete existing cassettes.
#    - spec/fixtures/vcr_cassettes/SecretFetcher/* for kredz interactions
# 2. Run a codespace dotcom (via codespace-compose) and start the dotcom server.
# 3. From the dotcom codespace run `start-actions` to bring up actions services (including kredz).
# 4. Run <github/github>/bin/create-dependabot-secrets.rb to setup secrets expected by the tests.
# 5. Update variables below to your local values:
#    - github_integration_node_id: GITHUB_INTEGRATION_NODE_ID value from env.local
#    - github_integration_next_global_id: GITHUB_INTEGRATION_NEXT_GLOBAL_ID value from env.local
#
# Troubleshooting:
# - Depending on how you've setup your dotcom instance the github_ids of the test orgs & repos may be different.
#   The test expects you've created the dependabot fixtures as the first step after bootstrapping the dotcom db.
# - To capture tests for enterprise mode you need to adjust the enterprise flag in `/workspaces/kredz/script/server`
#   (https://github.com/github/kredz/blob/main/script/server) and restart kredz: `service kredz-service restart`
# - If Dependabot secrets fail to create make sure DEPENDABOT_APP_RELAY_ID is properly set in
# .  `/workspaces/kredz/script/_serverenv` (https://github.com/github/kredz/blob/main/script/_serverenv)
RSpec.describe SecretFetcher, :vcr do
  let(:user) { FactoryBot.create(:account, github_id: 2) }
  let(:user_github_node_id) { "U_kgAC" }
  let(:user_repo_github_node_id) { "R_kgAQ" }
  let(:user_repo) { FactoryBot.create(:repo, github_id: 12, account: user) }
  let(:user_unknown_repo_github_node_id) { "MDEwOlJlcG9zaXRvcnk5OTk5OTk5" }
  let(:user_unknown_repo) { FactoryBot.create(:repo, github_id: 9999999, account: user) }
  let(:org) { FactoryBot.create(:account, :org, github_id: 4) }
  let(:org_github_node_id) { "O_kgAE" }
  let(:org_repo_github_node_id) { "R_kgAS" }
  let(:org_repo) { FactoryBot.create(:repo, github_id: 14, account: org) }
  let(:org_unknown_repo_github_node_id) { "MDEwOlJlcG9zaXRvcnk5OTk5OTk4" }
  let(:org_unknown_repo) { FactoryBot.create(:repo, github_id: 9999998, account: org) }
  let(:github_integration_next_global_id) { "A_kwEEAw" }

  context "in the cloud", :cloud do
    let(:fetcher) do
      kredz = Dependabot::Application.kredz_client

      global_id_api_client = Dependabot::Application.global_id_api_client

      described_class.new(
        github_integration_node_id: github_integration_next_global_id,
        kredz: kredz,
        global_id_api_client: global_id_api_client,
      )
    end

    before do
      allow_any_instance_of(GitHub::Twirp::GlobalId). # rubocop:disable RSpec/AnyInstance
        to receive(:get_github_next_global_id).with("U_kgAC").
        and_return("U_kgAC")

      allow_any_instance_of(GitHub::Twirp::GlobalId). # rubocop:disable RSpec/AnyInstance
        to receive(:get_github_next_global_id).with("R_kgAQ").
        and_return("R_kgAQ")

      allow_any_instance_of(GitHub::Twirp::GlobalId). # rubocop:disable RSpec/AnyInstance
        to receive(:get_github_next_global_id).with("O_kgAE").
        and_return("O_kgAE")

      allow_any_instance_of(GitHub::Twirp::GlobalId). # rubocop:disable RSpec/AnyInstance
        to receive(:get_github_next_global_id).with("R_kgAS").
        and_return("R_kgAS")

      allow_any_instance_of(GitHub::Twirp::GlobalId). # rubocop:disable RSpec/AnyInstance
        to receive(:get_github_next_global_id).with("A_kwEEAw").
        and_return("A_kwEEAw")

      allow_any_instance_of(GitHub::Twirp::GlobalId). # rubocop:disable RSpec/AnyInstance
        to receive(:get_github_next_global_id).with("MDEwOlJlcG9zaXRvcnk5OTk5OTk4").
        and_return("R_kgDOAJiWfg")

      allow_any_instance_of(GitHub::Twirp::GlobalId). # rubocop:disable RSpec/AnyInstance
        to receive(:get_github_next_global_id).with("MDEwOlJlcG9zaXRvcnk5OTk5OTk5").
        and_return("R_kgDOAJiWfw")

      allow_any_instance_of(GitHub::Twirp::GlobalId). # rubocop:disable RSpec/AnyInstance
        to receive(:get_github_next_global_id).with("R_kgAP").
        and_return("R_kgAP")
    end

    it "fetches repo secrets" do
      plaintext = fetcher.fetch(user_repo, user_github_node_id, user_repo_github_node_id, "REPO_TEST")

      expect(plaintext).to eq({
        REPO_TEST: "this is a Dependabot repo secret",
      }.stringify_keys)
    end

    it "fetches org secrets" do
      plaintext = fetcher.fetch(org_repo, org_github_node_id, org_repo_github_node_id, "ORG_TEST", "REPO_TEST")

      expect(plaintext).to eq({
        REPO_TEST: "this is a Dependabot repo secret",
        ORG_TEST: "this is a Dependabot org secret available to all repos",
      }.stringify_keys)
    end

    it "fetches only the requested secret when there are many" do
      plaintext = fetcher.fetch(org_repo, org_github_node_id, org_repo_github_node_id, "REPO_TEST")

      expect(plaintext).to eq({
        REPO_TEST: "this is a Dependabot repo secret",
      }.stringify_keys)
    end

    it "raises SecretNotFound for an unknown secret" do
      expect do
        fetcher.fetch(user_repo, user_github_node_id, user_repo_github_node_id, "MISSING_SECRET")
      end.to raise_error(SecretFetcher::SecretNotFound, "MISSING_SECRET")
    end

    it "raises SecretNotFound for an unknown repo with no org secrets" do
      expect do
        fetcher.fetch(user_unknown_repo, user_github_node_id, user_unknown_repo_github_node_id, "REPO_TEST")
      end.to raise_error(SecretFetcher::SecretNotFound, "REPO_TEST")
    end

    it "raises SecretNotRetrieved for a repo " do
      allow(fetcher).to receive(:repo_secrets).and_return(nil)
      expect do
        fetcher.fetch(user_unknown_repo, user_github_node_id, user_unknown_repo_github_node_id, "REPO_TEST")
      end.to raise_error(SecretFetcher::SecretNotRetrieved,
                         "Failed to fetch secrets for repository #{user_unknown_repo.name}")
    end

    it "raises SecretNotValid for an invalid secret" do
      # using different values for the public/private key triggers a DietEarthsmoke::CipherError
      different_key = '{"current":"1b9f551a1db4beb7","versions":{"1b9f551a1db4beb7":' \
                      '{"key_pair_algo":"LIBSODIUM-SEALED-BOX-CURVE25519-XSALSA20-POLY1305",' \
                      '"public_key":"8VcKdMnim5NcLIt9Z+/oxumzDcFE58V83Cyk89vHyEw=",' \
                      '"private_key":"4OATo3yq8iMvoqea86tQIHJrw2rbl6tsW5O2LnXND/k=",' \
                      '"symmetric_key_algo":"NULL","symmetric_key":null,"scoping_kdf_secret":' \
                      '"h5KFICjS76CWX5bDwXF6wYxJNm0aEVl/iAcaO0mjaXY="}}}'
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("EARTHSMOKE_DEPENDABOT_SECRETS_KEY").and_return(different_key)

      expect do
        fetcher.fetch(user_repo, user_github_node_id, user_repo_github_node_id, "REPO_TEST")
      end.to raise_error(SecretFetcher::SecretNotValid, "REPO_TEST")
    end

    it "fetches org secrets for an unknown repo" do
      plaintext = fetcher.fetch(org_unknown_repo, org_github_node_id, org_unknown_repo_github_node_id, "REPO_TEST")

      expect(plaintext).to eq({
        REPO_TEST: "this is a Dependabot org secret that will be overridden by a repo",
      }.stringify_keys)
    end
  end

  context "in enterprise mode", :enterprise do
    let!(:fetcher) do
      kredz = Dependabot::Application.kredz_client

      global_id_api_client = Dependabot::Application.global_id_api_client

      described_class.new(
        github_integration_node_id: github_integration_next_global_id,
        kredz: kredz,
        global_id_api_client: global_id_api_client,
      )
    end

    it "fetches repo secrets" do
      plaintext = fetcher.fetch(user_repo, user_github_node_id, user_repo_github_node_id, "REPO_TEST")

      expect(plaintext).to eq({
        REPO_TEST: "this is a Dependabot repo secret",
      }.stringify_keys)
    end

    it "fetches org secrets" do
      plaintext = fetcher.fetch(org_repo, org_github_node_id, org_repo_github_node_id, "ORG_TEST", "REPO_TEST")

      expect(plaintext).to eq({
        REPO_TEST: "this is a Dependabot repo secret",
        ORG_TEST: "this is a Dependabot org secret available to all repos",
      }.stringify_keys)
    end

    it "fetches only the requested secret when there are many" do
      plaintext = fetcher.fetch(org_repo, org_github_node_id, org_repo_github_node_id, "REPO_TEST")

      expect(plaintext).to eq({
        REPO_TEST: "this is a Dependabot repo secret",
      }.stringify_keys)
    end

    it "raises SecretNotFound for an unknown secret" do
      expect do
        fetcher.fetch(user_repo, user_github_node_id, user_repo_github_node_id, "MISSING_SECRET")
      end.to raise_error(SecretFetcher::SecretNotFound, "MISSING_SECRET")
    end

    it "raises SecretNotFound for an unknown repo with no org secrets" do
      expect do
        fetcher.fetch(user_unknown_repo, user_github_node_id, user_unknown_repo_github_node_id, "REPO_TEST")
      end.to raise_error(SecretFetcher::SecretNotFound, "REPO_TEST")
    end

    it "fetches org secrets for an unknown repo" do
      plaintext = fetcher.fetch(org_unknown_repo, org_github_node_id, org_unknown_repo_github_node_id, "REPO_TEST")

      expect(plaintext).to eq({
        REPO_TEST: "this is a Dependabot org secret that will be overridden by a repo",
      }.stringify_keys)
    end
  end
end
