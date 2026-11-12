# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/AnyInstance
RSpec.describe UpdateJobCredentialsSerializer, type: :serializer do
  include ProximaHelpers

  subject(:serialized_update_job) { described_class.new(update_job) }

  let(:update_job) { FactoryBot.create(:update_job) }
  let(:account) { update_job.update_config.account }

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:owner_github_node_id) { "MDEyOk9yZ2FuaXphdGlvbjMwODQ2MzQ1" }
  let(:repo_github_node_id) { "MDEwOlJlcG9zaXRvcnk4ODYzMjMzNA==" }
  let(:github_hostname) do
    if Dependabot.proxima?
      "staffship-01.ghe.com"
    else
      "github.com"
    end
  end
  let(:redis) { Dependabot.redis }

  before do
    update_job.update_config.update!(all_registries: true)
    redis.flushdb
  end

  describe "#credentials" do
    subject(:credentials) { serialized_update_job.credentials }

    before do
      stub_proxima_repo_request(repo_id: update_job.repo.github_id, fixture: "proxima_repo")

      allow(GitHubHelpers).
        to receive(:access_token_for).
        with(
          account: account,
          repo_ids: [update_job.update_config.repo.github_id],
          permissions: { contents: "read", metadata: "read" },
        ).
        and_return("a-secret-token")

      allow(GitHubHelpers).to receive(:access_token_for).
        with(account: account, permissions: nil, repo_ids: nil).
        and_return("unscoped-token")

      if Dependabot.proxima?
        # bypass this call for now as it is a workaround that requires a lot of stubbing
        allow_any_instance_of(DotcomRegistry).to receive(:credentials).and_return(nil)
      end
    end

    context "when the GitHub token has been set as a secret in Proxima", :proxima do
      before do
        stub_request(:get, "#{github_url}user/#{update_job.repo.account.github_id}").
          to_return(status: 200,
                    headers: { "Content-Type" => "application/json" },
                    body: { node_id: owner_github_node_id }.to_json)
        stub_request(:get, "#{github_url}repositories/#{update_job.repo.github_id}").
          to_return(status: 200,
                    headers: { "Content-Type" => "application/json" },
                    body: { node_id: repo_github_node_id }.to_json)
        allow(GitHubHelpers).
          to receive(:create_proxima_integration_access_token).
          and_return("a-secret-token-for-dotcom")
        allow_any_instance_of(DotcomRegistry).to receive(:credentials).and_call_original
      end

      let(:update_config) { update_job.update_config }

      it "includes the GitHub token" do
        expect(credentials).to include(
          {
            "type" => "git_source",
            "host" => "github.com",
            "username" => "proxima-service-identity",
            "password" => "a-secret-token-for-dotcom",
          }
        )
      end

      it "includes the access token for the Proxima stamp" do
        expect(credentials).to include(
          {
            "type" => "git_source",
            "host" => "staffship-01.ghe.com",
            "username" => "x-access-token",
            "password" => "a-secret-token",
            "accessible-repos" => [update_config.repo.full_name],
          }
        )
      end
    end

    it "populates increase-scope-endpoint" do
      expect(credentials).to match_array(
        [
          {
            "type" => "git_source",
            "host" => github_hostname,
            "username" => "x-access-token",
            "password" => "a-secret-token",
            "accessible-repos" => [update_job.update_config.repo.full_name],
          },
          {
            "type" => "jit_access",
            "credential-type" => "git_source",
            "host" => github_hostname,
            "endpoint" => "/update_jobs/#{update_job.id}/create_jit_access",
          },
        ]
      )
    end

    context "with another git_source provided by users" do
      let(:update_config) { update_job.update_config }

      before do
        FactoryBot.create(:registry,
                          :git,
                          source: update_config.repo,
                          credentials: {
                            url: "https://#{github_hostname}",
                            username: "github_username",
                            password: "${{ secrets.GITHUB_PASSWORD }}",
                          }.to_json)
        mock_secrets({ "GITHUB_PASSWORD" => "github_password" })
      end

      it "populates increase-scope-endpoint on the correct entry" do
        expect(credentials).to match_array(
          [
            {
              "type" => "git_source",
              "host" => github_hostname,
              "username" => "github_username",
              "password" => "github_password",
            },
            {
              "type" => "git_source",
              "host" => github_hostname,
              "username" => "x-access-token",
              "password" => "a-secret-token",
              "accessible-repos" => [update_config.repo.full_name],
            },
            {
              "type" => "jit_access",
              "credential-type" => "git_source",
              "host" => github_hostname,
              "endpoint" => "/update_jobs/#{update_job.id}/create_jit_access",
            },
          ]
        )
      end
    end

    context "when there are no credentials" do
      it "includes github credentials" do
        expect(credentials).to include(
          {
            "type" => "git_source",
            "host" => github_hostname,
            "username" => "x-access-token",
            "password" => "a-secret-token",
            "accessible-repos" => [update_job.update_config.repo.full_name],
          },
        )
      end

      context "with an inactive account" do
        before do
          account.transition_to!(
            :inactive,
            installation_id: account.current_installation_id,
          )
          update_job.update_config.reload
        end

        it "sets the github access token to 'expired_token'" do
          expect(credentials).to include(
            {
              "type" => "git_source",
              "host" => github_hostname,
              "username" => "x-access-token",
              "password" => "expired_token",
            },
          )
        end
      end

      context "with repository access" do
        before do
          update_job.update_config.update(package_manager: "go_modules")
          create_list(:repo, 2, account: account) do |repo|
            create(:repository_access, account: account, github_id: repo.github_id)
          end
        end

        it "requests every repository" do
          expect(GitHubHelpers).
            to receive(:access_token_for).
            with(
              account: account,
              repo_ids: account.repos.map(&:github_id),
              permissions: { contents: "read", metadata: "read" },
            ).
            and_return("a-secret-token")

          expect(credentials).to include(
            {
              "type" => "git_source",
              "host" => github_hostname,
              "username" => "x-access-token",
              "password" => "a-secret-token",
              "accessible-repos" => account.repos.map(&:full_name),
            },
          )
        end

        context "with error accessing multiple repositories" do
          before do
            expect(GitHubHelpers).
              to receive(:access_token_for).
              with(
                account: account,
                repo_ids: account.repos.map(&:github_id),
                permissions: { contents: "read", metadata: "read" },
              ).
              and_raise(Octokit::UnprocessableEntity)
          end

          it "retries with single repository" do
            expect(credentials).to include(
              {
                "type" => "git_source",
                "host" => github_hostname,
                "username" => "x-access-token",
                "password" => "a-secret-token",
                "accessible-repos" => [update_job.update_config.repo.full_name],
              },
            )
          end
        end
      end

      context "with cached jit accessed repo ids" do
        let(:other_repos) { create_list(:repo, 2, account: account) }

        before do
          update_job.update_config.add_jit_accessed_internal_github_repo_ids(other_repos.map(&:github_id))
        end

        it "requests every repository" do
          expect(GitHubHelpers).
            to receive(:access_token_for).
            with(
              account: account,
              repo_ids: [update_job.update_config.repo.github_id] + other_repos.map(&:github_id),
              permissions: { contents: "read", metadata: "read" },
            ).
            and_return("a-secret-token")

          expect(credentials).to eq(
            [
              {
                "type" => "git_source",
                "host" => github_hostname,
                "username" => "x-access-token",
                "password" => "a-secret-token",
                "accessible-repos" => account.repos.map(&:full_name),
              },
              {
                "type" => "jit_access",
                "credential-type" => "git_source",
                "host" => github_hostname,
                "endpoint" => "/update_jobs/#{update_job.id}/create_jit_access",
              },
            ],
          )
        end

        context "with error accessing multiple repositories" do
          before do
            expect(GitHubHelpers).
              to receive(:access_token_for).
              with(
                account: account,
                repo_ids: account.repos.map(&:github_id),
                permissions: { contents: "read", metadata: "read" },
              ).
              and_raise(Octokit::UnprocessableEntity)
          end

          it "retries with single repository" do
            expect(credentials).to eq(
              [
                {
                  "type" => "git_source",
                  "host" => github_hostname,
                  "username" => "x-access-token",
                  "password" => "a-secret-token",
                  "accessible-repos" => [update_job.update_config.repo.full_name],
                },
                {
                  "type" => "jit_access",
                  "credential-type" => "git_source",
                  "host" => github_hostname,
                  "endpoint" => "/update_jobs/#{update_job.id}/create_jit_access",
                },
              ],
            )
          end

          it "removes the errored repos from the update config's known list of jit accessed repos" do
            credentials

            expect(update_job.update_config.jit_accessed_internal_github_repo_ids).to eq([])
          end
        end
      end

      context "with too many repo ids for a single token" do
        let(:other_repos) do
          (1..((UpdateJobCredentialsSerializer::MAX_REPO_COUNT_PER_TOKEN / 10) + 1)).flat_map do |i|
            create_list(:repo, 10, account: account, name: "repo-#{i}")
          end
        end
        let(:all_repos) { [update_job.update_config.repo] + other_repos }
        let(:repo_batches) { all_repos.each_slice(UpdateJobCredentialsSerializer::MAX_REPO_COUNT_PER_TOKEN).to_a }

        before do
          update_job.update_config.add_jit_accessed_internal_github_repo_ids(other_repos.map(&:github_id))
        end

        it "requests multiple tokens" do
          expected_creds = repo_batches.each_with_index.map do |slice, index|
            expect(GitHubHelpers).
              to receive(:access_token_for).
              with(
                account: account,
                repo_ids: slice.map(&:github_id),
                permissions: { contents: "read", metadata: "read" },
              ).
              and_return("a-secret-token-#{index}")

            {
              "type" => "git_source",
              "host" => github_hostname,
              "username" => "x-access-token",
              "password" => "a-secret-token-#{index}",
              "accessible-repos" => slice.map(&:full_name),
            }
          end

          found_creds = credentials.select { |cred| cred["type"] == "git_source" }
          expect(found_creds.length).to be > 1
          expect(found_creds).to eq(expected_creds)
        end

        context "with error accessing jit accessed repos for a token" do
          it "removes the errored repos from the update config's known list of jit accessed repos" do
            expect(GitHubHelpers).
              to receive(:access_token_for).
              with(
                account: account,
                repo_ids: repo_batches[0].map(&:github_id),
                permissions: { contents: "read", metadata: "read" },
              ).
              and_raise(Octokit::UnprocessableEntity)

            repo_batches.drop(1).each_with_index.map do |slice, index|
              expect(GitHubHelpers).
                to receive(:access_token_for).
                with(
                  account: account,
                  repo_ids: slice.map(&:github_id),
                  permissions: { contents: "read", metadata: "read" },
                ).
                and_return("a-secret-token-#{index}")
            end

            credentials

            expect(update_job.update_config.jit_accessed_internal_github_repo_ids).
              to eq(repo_batches.drop(1).flatten.map(&:github_id))
          end
        end
      end

      context "with an out of date installation" do
        let(:dummy_account_synchronizer) do
          instance_double(SynchronizeAccountState, run: true)
        end
        let(:update_config) { update_job.update_config }

        before do
          allow(GitHubHelpers).
            to receive(:access_token_for).
            and_return(nil).
            and_raise(GitHubHelpers::InvalidInstallationId, 1)
          allow(SynchronizeAccountState).
            to receive(:new).
            with(account: account,
                 event_source: "api.get_update_job_credentials").
            and_return(dummy_account_synchronizer)
        end

        it "sets the github access token to '#{described_class::EXPIRED_TOKEN_RESPONSE}'" do
          expect(dummy_account_synchronizer).to receive(:run)
          expect(credentials).to include(
            {
              "type" => "git_source",
              "host" => github_hostname,
              "username" => "x-access-token",
              "password" => "expired_token",
            },
          )
        end

        it "raises an error if the config contains registries with secret credentials" do
          update_config.package_manager = "npm_and_yarn"
          create(
            :registry,
            source: update_config.repo,
            registry_type: "npm_registry",
            credentials: {
              url: "https://registry.npmjs.org",
              token: "${{secrets.MY_NPM_TOKEN}}",
            }.to_json,
          )

          expect(dummy_account_synchronizer).to receive(:run)
          expect { credentials }.to raise_error(SecretFetcher::SecretNotRetrieved)
        end
      end
    end

    context "when there is an irrelevant registry" do
      let(:update_job) { FactoryBot.create(:update_job) }
      let!(:registry) do
        FactoryBot.create(
          :registry, :docker,
          source: update_config.repo,
        )
      end
      let(:update_config) { update_job.update_config }

      before { update_config.package_manager = "bundler" }

      it "just includes github credentials" do
        expect(credentials).to include(
          {
            "type" => "git_source",
            "host" => github_hostname,
            "username" => "x-access-token",
            "password" => "a-secret-token",
            "accessible-repos" => [update_config.repo.full_name],
          },
        )
      end
    end

    def mock_secrets(secrets_hash)
      allow_any_instance_of(SecretFetcher).
        to receive(:fetch).with(update_config.repo, owner_github_node_id, repo_github_node_id, *secrets_hash.keys).
        and_return(secrets_hash)

      stub_request(:get, github_url + "user/#{account.github_id}").
        with(headers: { "Authorization" => "token unscoped-token" }).
        to_return(status: 200, body: fixture("github_responses/user_by_id.json"), headers: json_header)

      stub_request(:get, github_url + "repositories/#{update_config.repo.github_id}").
        with(headers: { "Authorization" => "token unscoped-token" }).
        to_return(status: 200, body: fixture("github_responses/repo.json"), headers: json_header)
    end

    context "when there is a terraform registry" do
      let(:update_job) { FactoryBot.create(:update_job) }
      let(:update_config) { update_job.update_config }

      before do
        update_config.package_manager = "terraform"
        FactoryBot.create(:registry, :terraform, source: update_config.repo)

        mock_secrets({ "TOKEN" => "0xdeadbeef" })
      end

      it "maps the token" do
        expect(serialized_update_job.credentials).
          to include(
            {
              "type" => "git_source",
              "host" => github_hostname,
              "username" => "x-access-token",
              "password" => "a-secret-token",
              "accessible-repos" => [update_config.repo.full_name],
            },
            {
              "type" => "terraform_registry",
              "host" => "registry.terraform.example.org",
              "token" => "0xdeadbeef",
            },
          )
      end
    end

    context "when there is a nuget registry without credentials" do
      let(:update_job) { FactoryBot.create(:update_job) }
      let(:update_config) { update_job.update_config }

      before do
        update_config.package_manager = "nuget"
        FactoryBot.create(:registry,
                          registry_type: "nuget_feed",
                          source: update_config.repo,
                          credentials: { "url" => "https://api.nuget.org/v3/index.json" }.to_json)
      end

      it "passes through the nuget registry without credentials" do
        expect(serialized_update_job.credentials).
          to include(
            {
              "type" => "git_source",
              "host" => github_hostname,
              "username" => "x-access-token",
              "password" => "a-secret-token",
              "accessible-repos" => [update_config.repo.full_name],
            },
            {
              "type" => "nuget_feed",
              "url" => "https://api.nuget.org/v3/index.json",
            },
          )
      end
    end

    context "when there is a relevant registry" do
      let(:update_job) { FactoryBot.create(:update_job) }
      let(:update_config) { update_job.update_config }

      before do
        update_config.package_manager = "bundler"
      end

      context "a single secret is referenced" do
        before { mock_secrets({ "GEMFURY" => "gemfury_secret" }) }

        it "includes the registry" do
          FactoryBot.create(
            :registry,
            source: update_config.repo,
          )

          expect(serialized_update_job.credentials).
            to include(
              {
                "type" => "git_source",
                "host" => github_hostname,
                "username" => "x-access-token",
                "password" => "a-secret-token",
                "accessible-repos" => [update_config.repo.full_name],
              },
              {
                "type" => "rubygems_server",
                "host" => "gem.fury.io",
                "token" => "gemfury_secret",
              },
            )
        end

        it "supports whitespace in the secret reference" do
          FactoryBot.create(
            :registry,
            source: update_config.repo,
            credentials: {
              url: "gem.fury.io",
              token: "${{ secrets.GEMFURY }}",
            }.to_json,
          )

          expect(serialized_update_job.credentials).
            to include(
              {
                "type" => "git_source",
                "host" => github_hostname,
                "username" => "x-access-token",
                "password" => "a-secret-token",
                "accessible-repos" => [update_config.repo.full_name],
              },
              {
                "type" => "rubygems_server",
                "host" => "gem.fury.io",
                "token" => "gemfury_secret",
              },
            )
        end

        it "trims whitespace from the secret" do
          mock_secrets({ "GEMFURY" => " gemfury_secret\n" })
          FactoryBot.create(
            :registry,
            source: update_config.repo,
          )

          expect(serialized_update_job.credentials).
            to include(
              {
                "type" => "git_source",
                "host" => github_hostname,
                "username" => "x-access-token",
                "password" => "a-secret-token",
                "accessible-repos" => [update_config.repo.full_name],
              },
              {
                "type" => "rubygems_server",
                "host" => "gem.fury.io",
                "token" => "gemfury_secret",
              },
            )
        end
      end

      context "when there is a git_source registry" do
        let(:update_job) { FactoryBot.create(:update_job) }
        let(:update_config) { update_job.update_config }

        before do
          update_config.package_manager = "bundler"
        end

        it "maps url to host" do
          FactoryBot.create(
            :registry,
            source: update_config.repo,
            registry_type: "git_source",
            credentials: {
              url: "https://gitlab.com",
              username: "acme",
              password: "${{secrets.MY_GITLAB_TOKEN}}",
            }.to_json,
          )
          mock_secrets({ "MY_GITLAB_TOKEN" => "super secret token" })

          expect(serialized_update_job.credentials).
            to include(
              {
                "type" => "git_source",
                "host" => github_hostname,
                "username" => "x-access-token",
                "password" => "a-secret-token",
                "accessible-repos" => [update_config.repo.full_name],
              },
              {
                "type" => "git_source",
                "host" => "gitlab.com",
                "username" => "acme",
                "password" => "super secret token",
              },
            )
        end
      end

      context "when there is a npm_registry registry" do
        let(:update_job) { FactoryBot.create(:update_job) }
        let(:update_config) { update_job.update_config }

        before do
          update_config.package_manager = "npm_and_yarn"
        end

        it "maps url to host" do
          FactoryBot.create(
            :registry,
            source: update_config.repo,
            registry_type: "npm_registry",
            credentials: {
              url: "https://registry.npmjs.org",
              token: "${{secrets.MY_NPM_TOKEN}}",
            }.to_json,
          )
          mock_secrets({ "MY_NPM_TOKEN" => "super secret token" })

          expect(serialized_update_job.credentials).
            to include(
              {
                "type" => "git_source",
                "host" => github_hostname,
                "username" => "x-access-token",
                "password" => "a-secret-token",
                "accessible-repos" => [update_config.repo.full_name],
              },
              {
                "type" => "npm_registry",
                "registry" => "registry.npmjs.org",
                "token" => "super secret token",
              },
            )
        end

        it "combines username+password" do
          FactoryBot.create(
            :registry,
            source: update_config.repo,
            registry_type: "npm_registry",
            credentials: {
              url: "https://registry.npmjs.org",
              username: "acme",
              password: "${{secrets.MY_NPM_PASSWORD}}",
            }.to_json,
          )
          mock_secrets({ "MY_NPM_PASSWORD" => "passw0rd" })

          expect(serialized_update_job.credentials).
            to include(
              {
                "type" => "git_source",
                "host" => github_hostname,
                "username" => "x-access-token",
                "password" => "a-secret-token",
                "accessible-repos" => [update_config.repo.full_name],
              },
              {
                "type" => "npm_registry",
                "registry" => "registry.npmjs.org",
                "token" => "acme:passw0rd",
              },
            )
        end

        it "puts metadata in the credentials" do
          FactoryBot.create(
            :registry,
            source: update_config.repo,
            registry_type: "npm_registry",
            credentials: {
              url: "https://registry.npmjs.org",
              username: "acme",
              password: "${{secrets.MY_NPM_PASSWORD}}",
              "replaces-base" => true,

            }.to_json,
          )
          mock_secrets({ "MY_NPM_PASSWORD" => "passw0rd" })

          expect(serialized_update_job.credentials).
            to include(
              {
                "type" => "git_source",
                "host" => github_hostname,
                "username" => "x-access-token",
                "password" => "a-secret-token",
                "accessible-repos" => [update_config.repo.full_name],
              },
              {
                "type" => "npm_registry",
                "registry" => "registry.npmjs.org",
                "token" => "acme:passw0rd",
                "replaces-base" => true,
              },
            )
        end
      end

      context "when there is a cargo_registry registry" do
        let(:update_job) { FactoryBot.create(:update_job) }
        let(:update_config) { update_job.update_config }

        before do
          update_config.package_manager = "cargo"
        end

        it "outputs credentials expected by the proxy" do
          FactoryBot.create(
            :registry,
            source: update_config.repo,
            registry_type: "cargo_registry",
            credentials: {
              "registry" => "cargo-registry-name",
              "url" => "https://cargo.example.com/path",
              "token" => "${{secrets.MY_CARGO_TOKEN}}",
            }.to_json,
          )
          mock_secrets(
            {
              "MY_CARGO_TOKEN" => "secr3t",
            }
          )

          expect(serialized_update_job.credentials).
            to include(
              {
                "type" => "git_source",
                "host" => github_hostname,
                "username" => "x-access-token",
                "password" => "a-secret-token",
                "accessible-repos" => [update_config.repo.full_name],
              },
              {
                "type" => "cargo_registry",
                "url" => "https://cargo.example.com/path",
                "token" => "secr3t",
                "registry" => "cargo-registry-name",
              },
            )
        end
      end

      context "when there is a pub_repository registry" do
        let(:update_job) { FactoryBot.create(:update_job) }
        let(:update_config) { update_job.update_config }

        before do
          update_config.package_manager = "pub"
        end

        it "outputs credentials expected by the proxy" do
          FactoryBot.create(
            :registry,
            source: update_config.repo,
            registry_type: "pub_repository",
            credentials: {
              "url" => "https://pub.example.com/path",
              "token" => "${{secrets.MY_PUB_TOKEN}}",
            }.to_json,
          )
          mock_secrets(
            {
              "MY_PUB_TOKEN" => "secr3t",
            }
          )

          expect(serialized_update_job.credentials).
            to include(
              {
                "type" => "git_source",
                "host" => github_hostname,
                "username" => "x-access-token",
                "password" => "a-secret-token",
                "accessible-repos" => [update_config.repo.full_name],
              },
              {
                "type" => "pub_repository",
                "url" => "https://pub.example.com/path",
                "token" => "secr3t",
              },
            )
        end
      end

      context "when there is a python_index registry" do
        let(:update_job) { FactoryBot.create(:update_job) }
        let(:update_config) { update_job.update_config }

        before do
          update_config.package_manager = "pip"
        end

        it "maps url to index-url" do
          FactoryBot.create(
            :registry,
            source: update_config.repo,
            registry_type: "python_index",
            credentials: {
              url: "https://gitlab.com",
              token: "${{secrets.MY_GITLAB_TOKEN}}",
              "replaces-base": true,
            }.to_json,
          )
          mock_secrets({ "MY_GITLAB_TOKEN" => "super secret token" })

          expect(serialized_update_job.credentials).
            to include(
              {
                "type" => "git_source",
                "host" => github_hostname,
                "username" => "x-access-token",
                "password" => "a-secret-token",
                "accessible-repos" => [update_config.repo.full_name],
              },
              {
                "type" => "python_index",
                "index-url" => "https://gitlab.com",
                "token" => "super secret token",
                "replaces-base" => true,
              },
            )
        end

        it "combines username+password" do
          FactoryBot.create(
            :registry,
            source: update_config.repo,
            registry_type: "python_index",
            credentials: {
              url: "https://gitlab.com",
              username: "acme",
              password: "${{secrets.MY_GITLAB_PASSWORD}}",
            }.to_json,
          )
          mock_secrets({ "MY_GITLAB_PASSWORD" => "passw0rd" })

          expect(serialized_update_job.credentials).
            to include(
              {
                "type" => "git_source",
                "host" => github_hostname,
                "username" => "x-access-token",
                "password" => "a-secret-token",
                "accessible-repos" => [update_config.repo.full_name],
              },
              {
                "type" => "python_index",
                "index-url" => "https://gitlab.com",
                "token" => "acme:passw0rd",
              },
            )
        end
      end

      context "when there is a nuget_feed registry" do
        let(:update_job) { FactoryBot.create(:update_job) }
        let(:update_config) { update_job.update_config }

        before do
          update_config.package_manager = "nuget"
        end

        it "combines username+password" do
          FactoryBot.create(
            :registry,
            source: update_config.repo,
            registry_type: "nuget_feed",
            credentials: {
              url: "https://gitlab.com",
              username: "acme",
              password: "${{secrets.MY_GITLAB_PASSWORD}}",
            }.to_json,
          )
          mock_secrets({ "MY_GITLAB_PASSWORD" => "passw0rd" })

          expect(serialized_update_job.credentials).
            to include(
              {
                "type" => "git_source",
                "host" => github_hostname,
                "username" => "x-access-token",
                "password" => "a-secret-token",
                "accessible-repos" => [update_config.repo.full_name],
              },
              {
                "type" => "nuget_feed",
                "url" => "https://gitlab.com",
                "token" => "acme:passw0rd",
              },
            )
        end
      end

      context "when there is a hex_organization registry" do
        let(:update_job) { FactoryBot.create(:update_job) }
        let(:update_config) { update_job.update_config }

        before do
          update_config.package_manager = "hex"
        end

        it "maps key to token" do
          FactoryBot.create(
            :registry,
            source: update_config.repo,
            registry_type: "hex_organization",
            credentials: {
              organization: "acme",
              key: "${{secrets.MY_HEX_KEY}}",
            }.to_json,
          )
          mock_secrets({ "MY_HEX_KEY" => "secr3t" })

          expect(serialized_update_job.credentials).
            to include(
              {
                "type" => "git_source",
                "host" => github_hostname,
                "username" => "x-access-token",
                "password" => "a-secret-token",
                "accessible-repos" => [update_config.repo.full_name],
              },
              {
                "type" => "hex_organization",
                "organization" => "acme",
                "token" => "secr3t",
              },
            )
        end
      end

      context "when there is a hex_repository registry" do
        let(:update_job) { FactoryBot.create(:update_job) }
        let(:update_config) { update_job.update_config }

        before do
          update_config.package_manager = "hex"
        end

        it "maps key to token" do
          FactoryBot.create(
            :registry,
            source: update_config.repo,
            registry_type: "hex_repository",
            credentials: {
              "url" => "https://hex.example.com",
              "repo" => "my_hex_repository",
              "auth-key" => "${{secrets.MY_HEX_KEY}}",
              "public-key-fingerprint" => "${{secrets.MY_HEX_PUBLIC_KEY_FINGERPRINT}}",
            }.to_json,
          )
          mock_secrets(
            {
              "MY_HEX_KEY" => "secr3t",
              "MY_HEX_PUBLIC_KEY_FINGERPRINT" => "pub1ck3y",
            }
          )

          expect(serialized_update_job.credentials).
            to include(
              {
                "type" => "git_source",
                "host" => github_hostname,
                "username" => "x-access-token",
                "password" => "a-secret-token",
                "accessible-repos" => [update_config.repo.full_name],
              },
              {
                "type" => "hex_repository",
                "url" => "https://hex.example.com",
                "repo" => "my_hex_repository",
                "auth-key" => "secr3t",
                "public-key-fingerprint" => "pub1ck3y",
              },
            )
        end
      end

      context "multiple secrets are referenced" do
        before { mock_secrets({ "GEMFURY1" => "gemfury_secret_1", "GEMFURY2" => "gemfury_secret_2" }) }

        it "supports multiple secrets in a single value" do
          FactoryBot.create(
            :registry,
            source: update_config.repo,
            credentials: {
              url: "gem.fury.io",
              token: "${{ secrets.GEMFURY1 }} plus ${{ secrets.GEMFURY2 }}",
            }.to_json,
          )

          expect(serialized_update_job.credentials).
            to include(
              {
                "type" => "git_source",
                "host" => github_hostname,
                "username" => "x-access-token",
                "password" => "a-secret-token",
                "accessible-repos" => [update_config.repo.full_name],
              },
              {
                "type" => "rubygems_server",
                "host" => "gem.fury.io",
                "token" => "gemfury_secret_1 plus gemfury_secret_2",
              },
            )
        end
      end

      context "the owner_github_node_id lookup fails with not found" do
        before do
          stub_request(:get, github_url + "user/#{account.github_id}").
            to_return(status: 404, body: fixture("github_responses/user_not_found.json"), headers: json_header)
        end

        it "raises an error" do
          create(
            :registry,
            source: update_config.repo,
          )

          expect { serialized_update_job.credentials }.
            to raise_error(Octokit::NotFound)
        end
      end

      context "the owner_github_node_id lookup fails with unauthorized" do
        before do
          stub_request(:get, github_url + "user/#{account.github_id}").
            to_return(status: 401, headers: json_header)
        end

        it "raises an error" do
          create(:registry, source: update_config.repo)

          expect { serialized_update_job.credentials }.
            to raise_error(SecretFetcher::SecretNotRetrieved)
          expect(WebMock).to have_requested(:get, github_url + "user/#{account.github_id}").times(2)
        end
      end
    end

    context "when there is an unselected relevant registry" do
      let(:update_job) { FactoryBot.create(:update_job) }
      let!(:registry) do
        FactoryBot.create(
          :registry, :bundler,
          source: update_config.repo,
        )
      end
      let(:update_config) { update_job.update_config }

      before do
        update_config.update(package_manager: "bundler", all_registries: false)
      end

      it "includes only the default token" do
        expect(serialized_update_job.credentials).
          to include(
            {
              "type" => "git_source",
              "host" => github_hostname,
              "username" => "x-access-token",
              "password" => "a-secret-token",
              "accessible-repos" => [update_config.repo.full_name],
            },
          )
      end
    end

    context "when running in enterprise mode", :enterprise do
      let(:enterprise_hostname) { "ghes-host.github.net" }
      let(:dotcom_hostname) { "github.com" }

      before do
        allow(Dependabot::Application).to receive(:target_github_hostname).and_return(enterprise_hostname)
        allow(Dependabot).to receive(:enterprise?).and_return(true)
      end

      context "when the relevant secret has not been provided" do
        it "does not include dotcom credentials unless the relevant secret has been provided" do
          stub_request(:post, %r{enterprise/tokens}).and_return(status: 404)

          expect(serialized_update_job.credentials).
            to include(
              {
                "type" => "git_source",
                "host" => enterprise_hostname,
                "username" => "x-access-token",
                "password" => "a-secret-token",
                "accessible-repos" => [update_job.update_config.repo.full_name],
              },
            )
        end
      end

      context "when dotcom credentials are provided (ex: private registry)" do
        let(:update_config) { update_job.update_config }

        before do
          FactoryBot.create(:registry,
                            :git,
                            source: update_config.repo,
                            credentials: {
                              url: "https://#{dotcom_hostname}",
                              username: "github_username",
                              password: "${{ secrets.GITHUB_PASSWORD }}",
                            }.to_json)
          mock_secrets({ "GITHUB_PASSWORD" => "github_password" })
        end

        it "does not try to use the relevant user-provided token" do
          expect(serialized_update_job.credentials).
            to include(
              {
                "type" => "git_source",
                "host" => enterprise_hostname,
                "username" => "x-access-token",
                "password" => "a-secret-token",
                "accessible-repos" => [update_job.update_config.repo.full_name],
              },
              {
                "type" => "git_source",
                "host" => dotcom_hostname,
                "username" => "github_username",
                "password" => "github_password",
              },
            )
        end
      end

      context "when no other dotcom credentials are provided" do
        it "uses the user-provided token" do
          dotcom_token = "dotcom-token"
          stub_request(:post, %r{enterprise/tokens}).
            and_return(
              status: 201,
              headers: { "Content-Type" => "application/json" },
              body: { token: dotcom_token }.to_json
            )

          expect(serialized_update_job.credentials).
            to include(
              {
                "type" => "git_source",
                "host" => enterprise_hostname,
                "username" => "x-access-token",
                "password" => "a-secret-token",
                "accessible-repos" => [update_job.update_config.repo.full_name],
              },
              {
                "type" => "git_source",
                "host" => dotcom_hostname,
                "username" => "x-access-token",
                "password" => dotcom_token,
              },
            )
        end
      end
    end
  end
end
# rubocop:enable RSpec/AnyInstance
