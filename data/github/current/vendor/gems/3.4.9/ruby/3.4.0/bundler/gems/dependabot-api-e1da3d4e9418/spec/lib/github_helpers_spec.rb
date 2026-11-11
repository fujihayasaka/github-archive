# frozen_string_literal: true

require "rails_helper"
require "github_helpers"

RSpec.describe GitHubHelpers do
  let(:github_url) { "https://internal-api.service.iad.github.net" }
  let(:json_header) { { "Content-Type" => "application/json" } }

  describe ".access_token_for" do
    subject(:create_access_token) do
      described_class.access_token_for(account: account)
    end

    let(:account) do
      FactoryBot.create(:account, :active)
    end
    let(:global_access_token_url) do
      "#{github_url}/app/global/access_tokens"
    end
    let(:global_access_token) do
      erb_fixture("github_responses/global_access_token.json")
    end
    let(:install_access_token_url) do
      "#{github_url}/app/installations/#{installation_id}/access_tokens"
    end
    let(:install_access_token) do
      erb_fixture("github_responses/installation_access_token.json")
    end

    let(:installation_id) do
      account.current_installation_id
    end

    before do
      stub_request(:post, global_access_token_url).
        with(body: { target_id: account.github_id }.to_json).
        to_return(
          status: 200,
          body: global_access_token,
          headers: json_header,
        )

      stub_request(:post, install_access_token_url).
        with(body: {}.to_json).
        to_return(
          status: 200,
          body: install_access_token,
          headers: json_header,
        )
    end

    context "with the global_tokens feature enabled" do
      before { account.enable_feature(:global_tokens) }

      it "mints a token via the global apps endpoint" do
        create_access_token
        expect(WebMock).to have_requested(:post, global_access_token_url).once
      end
    end

    context "with the global_tokens feature disabled" do
      before { account.disable_feature(:global_tokens) }

      it "mints a token via the installation endpoint" do
        create_access_token
        expect(WebMock).to have_requested(:post, install_access_token_url).once
      end
    end
  end

  describe ".global_access_token_for" do
    subject(:create_access_token) do
      described_class.global_access_token_for(target_id)
    end

    let(:target_id) { 123 }
    let(:redis) { Dependabot.redis }
    let(:github_access_token) do
      erb_fixture("github_responses/global_access_token.json")
    end
    let(:access_token_url) { "#{github_url}/app/global/access_tokens" }

    before { redis.flushdb }

    before do
      stub_request(:post, access_token_url).
        with(body: { target_id: target_id }.to_json).
        to_return(status: 200, body: github_access_token, headers: json_header)
    end

    context "when there is no cached account ID" do
      it { is_expected.to eq("v1.exampletokenfromgithubinityesitisforsure") }

      it "creates an access token with GitHub" do
        create_access_token
        expect(WebMock).to have_requested(:post, access_token_url)
      end

      it "emits metrics: create_access_token" do
        expect(MetricsClient).to receive(:time).with("create_access_token", tags: {
                                                       global: true,
                                                       repo_ids_bucket: 0,
                                                     })
        create_access_token
      end
    end

    context "when there is a cached account ID" do
      before { described_class.global_access_token_for(target_id) }

      it { is_expected.to eq("v1.exampletokenfromgithubinityesitisforsure") }

      it "doesn't hit GitHub a second time" do
        expect(Octokit::Client).not_to receive(:new)
        create_access_token
      end

      it "doesn't emit metric: create_access_token" do
        expect(MetricsClient).not_to receive(:time).with("create_access_token", tag: anything)
        create_access_token
      end
    end

    context "when given repo IDs" do
      subject(:create_access_token) do
        described_class.global_access_token_for(
          target_id,
          repo_ids: [54321]
        )
      end

      context "when there is a cached account ID without repo IDs" do
        before do
          described_class.global_access_token_for(target_id)

          stub_request(:post, access_token_url).
            with(body: { target_id: target_id }.to_json).
            to_return(
              status: 500,
              body: github_access_token,
              headers: json_header,
            )
          stub_request(:post, access_token_url).
            with(body: {
              target_id: target_id,
              repository_ids: [54321],
            }.to_json).
            to_return(
              status: 200,
              body: github_access_token.gsub("example", "ascoped"),
              headers: json_header
            )
        end

        it { is_expected.to eq("v1.ascopedtokenfromgithubinityesitisforsure") }

        it "creates an access token with GitHub" do
          create_access_token
          expect(WebMock).to have_requested(:post, access_token_url).twice
        end

        it "emits metrics: create_access_token" do
          expect(MetricsClient).to receive(:time).with("create_access_token", tags: {
                                                         global: true,
                                                         repo_ids_bucket: 1,
                                                       })
          create_access_token
        end
      end

      context "when there is a cached account ID with the same repo IDs" do
        before do
          stub_request(:post, access_token_url).
            with(body: { target_id: target_id }.to_json).
            to_return(
              status: 500,
              body: github_access_token,
              headers: json_header,
            )
          stub_request(:post, access_token_url).
            with(body: {
              target_id: target_id,
              repository_ids: [54321],
            }.to_json).
            to_return(
              status: 200,
              body: github_access_token.gsub("example", "ascoped"),
              headers: json_header
            )
          described_class.global_access_token_for(
            target_id,
            repo_ids: [54321],
          )
        end

        it { is_expected.to eq("v1.ascopedtokenfromgithubinityesitisforsure") }

        it "doesn't hit GitHub a second time" do
          expect(Octokit::Client).not_to receive(:new)
          create_access_token
        end
      end

      context "and permissions" do
        subject(:create_access_token) do
          described_class.global_access_token_for(
            target_id,
            repo_ids: [54321],
            permissions: { contents: "read" },
          )
        end

        before do
          stub_request(:post, access_token_url).
            with(body: { target_id: target_id }.to_json).
            to_return(
              status: 500,
              body: github_access_token,
              headers: json_header,
            )
          stub_request(:post, access_token_url).
            with(
              body: {
                target_id: target_id,
                repository_ids: [54321],
                permissions: { contents: "read" },
              }.to_json
            ).
            to_return(
              status: 200,
              body: github_access_token.gsub("example", "ascoped"),
              headers: json_header
            )
        end

        it { is_expected.to eq("v1.ascopedtokenfromgithubinityesitisforsure") }
      end
    end
  end

  describe ".installation_access_token_for" do
    subject(:create_access_token) do
      described_class.installation_access_token_for(installation_id)
    end

    let(:installation_id) { 123 }
    let(:github_access_token) do
      erb_fixture("github_responses/installation_access_token.json")
    end
    let(:access_token_url_regex) do
      %r{#{Regexp.escape(github_url)}/app/installations/[0-9]*/access_tokens}
    end
    let(:redis) { Dependabot.redis }

    before { redis.flushdb }

    before do
      stub_request(:post, access_token_url_regex).
        with(body: {}.to_json).
        to_return(status: 200, body: github_access_token, headers: json_header)
    end

    context "when there is no cached installation ID" do
      it { is_expected.to eq("v1.exampletokenfromgithubinityesitisforsure") }

      it "creates an access token with GitHub" do
        create_access_token
        expect(WebMock).to have_requested(:post, access_token_url_regex)
      end

      it "emits metrics: create_access_token" do
        expect(MetricsClient).to receive(:time).with("create_access_token", tags: {
                                                       global: false,
                                                       repo_ids_bucket: 0,
                                                     })
        create_access_token
      end

      context "and GitHub 404s" do
        before do
          stub_request(:post, access_token_url_regex).to_return(status: 404)
        end

        it "raises an error" do
          expect { create_access_token }.
            to raise_error(GitHubHelpers::InvalidInstallationId)
        end
      end
    end

    context "when there is a cached installation ID" do
      before { described_class.installation_access_token_for(installation_id) }

      it { is_expected.to eq("v1.exampletokenfromgithubinityesitisforsure") }

      it "doesn't hit GitHub a second time" do
        expect(Octokit::Client).not_to receive(:new)
        create_access_token
      end
    end

    context "when given repo IDs" do
      subject(:create_access_token) do
        described_class.installation_access_token_for(
          installation_id,
          repo_ids: [54321]
        )
      end

      context "when there is a cached installation ID without repo IDs" do
        before do
          described_class.installation_access_token_for(installation_id)

          stub_request(:post, access_token_url_regex).
            with(body: {}.to_json).
            to_return(
              status: 500,
              body: github_access_token,
              headers: json_header,
            )
          stub_request(:post, access_token_url_regex).
            with(body: { repository_ids: [54321] }.to_json).
            to_return(
              status: 200,
              body: github_access_token.gsub("example", "ascoped"),
              headers: json_header
            )
        end

        it { is_expected.to eq("v1.ascopedtokenfromgithubinityesitisforsure") }

        it "creates an access token with GitHub" do
          create_access_token
          expect(WebMock).to have_requested(:post, access_token_url_regex).twice
        end

        it "emits metrics: create_access_token" do
          expect(MetricsClient).to receive(:time).with("create_access_token", tags: {
                                                         global: false,
                                                         repo_ids_bucket: 1,
                                                       })
          create_access_token
        end
      end

      context "when there is a cached installation ID with the same repo IDs" do
        before do
          stub_request(:post, access_token_url_regex).
            with(body: {}.to_json).
            to_return(
              status: 500,
              body: github_access_token,
              headers: json_header,
            )
          stub_request(:post, access_token_url_regex).
            with(body: { repository_ids: [54321] }.to_json).
            to_return(
              status: 200,
              body: github_access_token.gsub("example", "ascoped"),
              headers: json_header
            )
          described_class.installation_access_token_for(
            installation_id,
            repo_ids: [54321],
          )
        end

        it { is_expected.to eq("v1.ascopedtokenfromgithubinityesitisforsure") }

        it "doesn't hit GitHub a second time" do
          expect(Octokit::Client).not_to receive(:new)
          create_access_token
        end
      end

      context "and permissions" do
        subject(:create_access_token) do
          described_class.installation_access_token_for(
            installation_id,
            repo_ids: [54321],
            permissions: { contents: "read" },
          )
        end

        before do
          stub_request(:post, access_token_url_regex).
            with(body: {}.to_json).
            to_return(
              status: 500,
              body: github_access_token,
              headers: json_header,
            )
          stub_request(:post, access_token_url_regex).
            with(
              body: {
                repository_ids: [54321],
                permissions: { contents: "read" },
              }.to_json,
            ).
            to_return(
              status: 200,
              body: github_access_token.gsub("example", "ascoped"),
              headers: json_header
            )
        end

        it { is_expected.to eq("v1.ascopedtokenfromgithubinityesitisforsure") }
      end
    end

    context "when given many repo IDs" do
      subject(:create_access_token) do
        described_class.installation_access_token_for(
          installation_id,
          repo_ids: [*1..25],
        )
      end

      before do
        stub_request(:post, access_token_url_regex).
          to_return(
            status: 200,
            body: github_access_token.gsub("example", "ascoped"),
            headers: json_header
          )
      end

      it "emits metrics: create_access_token" do
        expect(MetricsClient).to receive(:time).with("create_access_token", tags: {
                                                       global: false,
                                                       repo_ids_bucket: 20,
                                                     })
        create_access_token
      end
    end

    context "when given an invalid repo ID" do
      subject(:create_access_token) do
        described_class.installation_access_token_for(
          installation_id,
          repo_ids: [54321]
        )
      end

      before do
        stub_request(:post, access_token_url_regex).
          to_return(
            status: 422,
            body: fixture("github_responses/repo_installation_missing.json"),
            headers: json_header
          )
      end

      it "raises exception" do
        expect { create_access_token }.
          to raise_error(Octokit::UnprocessableEntity)
      end
    end
  end

  describe ".delete_cached_access_token_for" do
    subject(:delete_cached_access_token) do
      described_class.delete_cached_access_token_for(account: account)
    end

    let(:account) do
      FactoryBot.create(:account, :active)
    end
    let(:global_access_token_url) do
      "#{github_url}/app/global/access_tokens"
    end
    let(:global_access_token) do
      erb_fixture("github_responses/global_access_token.json")
    end
    let(:install_access_token_url) do
      "#{github_url}/app/installations/#{installation_id}/access_tokens"
    end
    let(:install_access_token) do
      erb_fixture("github_responses/installation_access_token.json")
    end

    let(:installation_id) do
      account.current_installation_id
    end

    before do
      stub_request(:post, global_access_token_url).
        with(body: { target_id: account.github_id }.to_json).
        to_return(
          status: 200,
          body: global_access_token,
          headers: json_header,
        )

      stub_request(:post, install_access_token_url).
        with(body: {}.to_json).
        to_return(
          status: 200,
          body: install_access_token,
          headers: json_header,
        )
    end

    context "with the global_tokens feature enabled" do
      before { account.enable_feature(:global_tokens) }

      it "is a no-op if nothing is cached" do
        expect(delete_cached_access_token).to be(false)
      end

      it "is a no-op if an install token is cached" do
        described_class.installation_access_token_for(installation_id)
        expect(delete_cached_access_token).to be(false)
      end

      it "deletes a cached global token" do
        described_class.global_access_token_for(account.github_id)
        expect(delete_cached_access_token).to be(true)
      end
    end

    context "with the global_tokens feature disabled" do
      before { account.disable_feature(:global_tokens) }

      it "is a no-op if nothing is cached" do
        expect(delete_cached_access_token).to be(false)
      end

      it "deletes a cached installation token" do
        described_class.installation_access_token_for(installation_id)
        expect(delete_cached_access_token).to be(true)
      end

      it "is a no-op if a global token is cached" do
        described_class.global_access_token_for(account.github_id)
        expect(delete_cached_access_token).to be(false)
      end
    end
  end

  describe ".delete_cached_global_access_token_for" do
    subject(:delete_cached_access_token) do
      described_class.
        delete_cached_global_access_token_for(target_id)
    end

    let(:target_id) { 123 }
    let(:redis) { Dependabot.redis }

    let(:access_token_url) do
      "#{github_url}/app/global/access_tokens"
    end

    let(:github_access_token) do
      erb_fixture("github_responses/global_access_token.json")
    end

    before do
      stub_request(:post, access_token_url).
        to_return(
          status: 200,
          body: github_access_token,
          headers: json_header,
        )

      redis.flushdb
    end

    context "with no cached access token" do
      it { is_expected.to be(false) }
    end

    context "with a cached access token" do
      before do
        described_class.global_access_token_for(target_id)
      end

      it { is_expected.to be(true) }
    end

    context "when given repo IDs" do
      subject(:delete_cached_access_token) do
        described_class.delete_cached_global_access_token_for(
          target_id,
          repo_ids: [54321],
        )
      end

      context "with a cached access token" do
        before do
          # Cache an access token
          described_class.global_access_token_for(
            target_id,
            repo_ids: [54321],
          )
        end

        it { is_expected.to be(true) }

        context "for a different repo ID" do
          subject(:delete_cached_access_token) do
            described_class.delete_cached_global_access_token_for(
              target_id,
              repo_ids: [54322],
            )
          end

          it { is_expected.to be(false) }
        end

        context "and permissions" do
          subject(:delete_cached_access_token) do
            described_class.delete_cached_global_access_token_for(
              target_id,
              repo_ids: [54321],
              permissions: { contents: "read" },
            )
          end

          before do
            # Cache an access token
            described_class.global_access_token_for(
              target_id,
              repo_ids: [54321],
              permissions: { contents: "read" },
            )
          end

          it { is_expected.to be(true) }
        end
      end
    end
  end

  describe ".octokit_client_for" do
    subject(:octokit_client) do
      described_class.
        octokit_client_for
    end

    let(:github_org_url) { "https://api.github.com/orgs/github" }

    before do
      stub_request(:get, github_org_url).
        to_return(status: 200, body: "{}", headers: json_header)
    end

    context "used to make a request" do
      it "uses the default dependabot user-agent" do
        octokit_client.organization("github")
        expect(WebMock).to have_requested(:get, github_org_url).
          with(headers: { "User-Agent" => %r{github/dependabot-api \(Octokit Ruby Gem \d+\.\d+\.\d+\)} })
      end
    end
  end

  describe ".delete_cached_installation_access_token_for" do
    subject(:delete_cached_access_token) do
      described_class.
        delete_cached_installation_access_token_for(installation_id)
    end

    let(:installation_id) { 123 }
    let(:redis) { Dependabot.redis }

    before { redis.flushdb }

    context "with no cached access token" do
      it { is_expected.to be(false) }
    end

    context "with a cached access token" do
      before do
        github_regex = Regexp.escape(github_url)
        access_token_url_regex =
          %r{#{github_regex}/app/installations/[0-9]*/access_tokens}
        github_access_token =
          erb_fixture("github_responses/installation_access_token.json")
        stub_request(:post, access_token_url_regex).
          to_return(
            status: 200,
            body: github_access_token,
            headers: json_header,
          )

        # Cache an access token
        described_class.installation_access_token_for(installation_id)
      end

      it { is_expected.to be(true) }
    end

    context "when given repo IDs" do
      subject(:delete_cached_access_token) do
        described_class.delete_cached_installation_access_token_for(
          installation_id,
          repo_ids: [54321],
        )
      end

      context "with a cached access token" do
        before do
          access_token_url_regex =
            %r{
              #{Regexp.escape(github_url)}/app/
              installations/[0-9]*/access_tokens
            }x
          github_access_token =
            erb_fixture("github_responses/installation_access_token.json")
          stub_request(:post, access_token_url_regex).
            to_return(
              status: 200,
              body: github_access_token,
              headers: json_header,
            )

          # Cache an access token
          described_class.installation_access_token_for(
            installation_id,
            repo_ids: [54321],
          )
        end

        it { is_expected.to be(true) }

        context "for a different repo ID" do
          subject(:delete_cached_access_token) do
            described_class.delete_cached_installation_access_token_for(
              installation_id,
              repo_ids: [54322],
            )
          end

          it { is_expected.to be(false) }
        end

        context "and permissions" do
          subject(:delete_cached_access_token) do
            described_class.delete_cached_installation_access_token_for(
              installation_id,
              repo_ids: [54321],
              permissions: { contents: "read" },
            )
          end

          before do
            # Cache an access token
            described_class.installation_access_token_for(
              installation_id,
              repo_ids: [54321],
              permissions: { contents: "read" },
            )
          end

          it { is_expected.to be(true) }
        end
      end
    end
  end

  describe GitHubHelpers::ClientWithRetries do
    subject(:client) { described_class.new(**args) }

    context "when caching is not specified" do
      let(:args) { { access_token: "junk" } }

      it "does not include caching middleware" do
        expect(client.middleware.handlers).not_to include(Faraday::EtagCache)
      end
    end

    context "when caching is specified" do
      let(:args) { { access_token: "junk", etag_caching: true } }

      it "includes caching middleware" do
        expect(client.middleware.handlers).to include(Faraday::EtagCache)
      end
    end
  end
end
