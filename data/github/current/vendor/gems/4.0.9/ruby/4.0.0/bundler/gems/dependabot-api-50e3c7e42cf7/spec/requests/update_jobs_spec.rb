# frozen_string_literal: true

require "rails_helper"

require "dependabot/pull_request_creator"
require "dependabot/pull_request_updater"

RSpec.describe "/update_jobs", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include MonolithSettingsHelper
  include ProximaHelpers

  # Helper to serialize experiments hash the same way the JSON API serializer does
  def serialized_experiments(update_job)
    update_job.experiments.transform_keys { |k| k.to_s.dasherize }.to_json
  end

  let(:token) { RbNaCl::Random.random_bytes(RbNaCl::SecretBox.key_bytes) }
  let(:base64_job_token) { Base64.strict_encode64(token) }
  let(:hashed_token) { Base64.strict_encode64(RbNaCl::Hash.sha256(token)) }
  let(:token_checksum) { Base62.encode(Zlib.crc32(base64_job_token)).rjust(6, Base62::PRIMITIVES[0]) }
  let(:external_job_token) do
    UpdateJob::DEPENDABOT_JOB_TOKEN_PREFIX +
      base64_job_token +
      token_checksum
  end

  describe "GET /update_jobs/:id/details" do
    let(:header) do
      { "Content-Type" => "application/json", "Authorization" => external_job_token }
    end

    let(:update_config) { FactoryBot.create(:update_config) }
    let(:update_job) do
      FactoryBot.create(
        :update_job, :processing,
        id: 1001,
        update_config: update_config,
        hashed_token: hashed_token,
      )
    end
    let(:previous_update_job) do
      FactoryBot.create(:update_job, update_config: update_config)
    end

    # 3 specifies the number of fractional digits for seconds
    let(:timestamp) do
      Time.parse("2020-04-01 00:00 +0000").utc.iso8601(3)
    end

    before do
      FactoryBot.create(
        :pull_request,
        github_number: 1010, # Explicit PR number to match details.json.erb
        update_job: previous_update_job,
        update_config: previous_update_job.update_config,
      )
      FactoryBot.create(
        :ignore_condition,
        update_config: update_config,
        created_at: timestamp,
        updated_at: timestamp
      )
      FactoryBot.create(
        :ignore_condition,
        :ignore_patch,
        update_config: update_config,
        created_at: timestamp,
        updated_at: timestamp
      )
    end

    context "when a valid authorization header is provided" do
      before do
        travel_to Time.parse("2020-04-01 00:00 +0000").utc

        stub_monolith_settings(security_updates_grouping_enabled: false)
        stub_proxima_repo_request(repo_id: update_job.repo.github_id, fixture: "proxima_repo")
      end

      it "serializes the update job" do
        get "/update_jobs/#{update_job.id}/details", headers: header

        expect(response).to have_http_status(:ok)

        expect(JSON.parse(response.body)).
          to eq(JSON.parse(erb_fixture("api_responses/update_jobs/details.json",
                                       updated_at: timestamp,
                                       experiments: serialized_experiments(update_job))))
      end

      context "when vendoring is enabled for the update job's config" do
        before do
          update_config.update(vendor: true)
          # Override the existing PR to use the vendor-specific PR number
          PullRequest.where(update_config: update_config).update(github_number: 1011)
        end

        it "serializes the update job" do
          get "/update_jobs/#{update_job.id}/details", headers: header

          expect(response).to have_http_status(:ok)

          expect(JSON.parse(response.body)).
            to eq(JSON.parse(erb_fixture("api_responses/update_jobs/vendor_dependencies.json",
                                         updated_at: timestamp,
                                         experiments: serialized_experiments(update_job))))
        end
      end

      context "with a security only update job" do
        let(:update_job) do
          FactoryBot.create(
            :update_job, :enqueued, :security,
            id: 1001,
            update_config: update_config,
            hashed_token: hashed_token,
          )
        end

        before do
          # Override the existing PR to use a designated PR number
          PullRequest.where(update_config: update_config).update(github_number: 1012)
        end

        it "serializes the update job" do
          allow(GitHubSecurityAdvisory).to receive(:fetch).and_return([])

          get "/update_jobs/#{update_job.id}/details", headers: header

          expect(response).to have_http_status(:ok)

          expect(JSON.parse(response.body)).
            to eq(JSON.parse(erb_fixture("api_responses/update_jobs/details_security_only.json",
                                         updated_at: timestamp,
                                         experiments: serialized_experiments(update_job))))
        end
      end
    end

    context "with an update PR job for a Dependency Group" do
      let(:dependency_group) do
        FactoryBot.create(
          :dependency_group,
          update_config: update_config,
          name: "very-extra",
          rules: { patterns: ["extra-*"] }
        )
      end

      let(:previous_group_update_job) do
        FactoryBot.create(:update_job, update_config: update_config)
      end

      before do
        # Override the existing PR to use the group-specific PR number for existing-pull-requests
        PullRequest.where(update_config: update_config).update(github_number: 1013)

        # Create an existing group PR we are refreshing with explicit number
        pr = FactoryBot.create(
          :pull_request,
          github_number: 1014, # Explicit PR number for details_group_rebase.json.erb
          update_job: previous_group_update_job,
          update_config: previous_group_update_job.update_config,
          grouped_update: true,
          dependency_group: dependency_group,
          dependencies: [
            {
              name: "extra-business",
              version: "1.0.0",
              previous_version: "0.9.9",
              requirements: [],
              previous_requirements: [],
              package_manager: "bundler",
            },
          ]
        )
        pr.transition_to!(:updating)
        update_job.pull_request_transition = pr.last_transition
        update_job.command = :recreate
        update_job.save!

        stub_proxima_repo_request(repo_id: update_job.repo.github_id, fixture: "proxima_repo")
      end

      it "serializes the update job" do
        get "/update_jobs/#{update_job.id}/details", headers: header

        expect(response).to have_http_status(:ok)

        expect(JSON.parse(response.body)).
          to eq(JSON.parse(erb_fixture("api_responses/update_jobs/details_group_rebase.json",
                                       updated_at: timestamp,
                                       experiments: serialized_experiments(update_job))))
      end
    end
  end

  describe "POST /update_jobs/:id/create_jit_access" do
    subject(:create_jit_access_token) do
      post(
        "/update_jobs/#{update_job.id}/create_jit_access",
        headers: header,
        params: params,
      )
    end

    let(:header) do
      { "Content-Type" => "application/json", "Authorization" => external_job_token }
    end
    let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }

    let(:tokens_service) { instance_double(GitHub::Twirp::Tokens) }
    let(:new_token) { "new-token" }

    before do
      allow(GitHub::Twirp::Tokens).to receive(:new).and_return(tokens_service)
      allow(tokens_service).to receive(:create_jit_access).and_return(
        GitHub::Twirp::Tokens::JitAccessResponse.new(token: new_token, repository_id: update_job.repo.github_id)
      )
    end

    context "with no job matching the provided token" do
      let(:params) { { account: "org", repository: "repo" }.to_json }
      let(:update_job) { create(:update_job, :processing, hashed_token: "no-match") }

      it "is forbidden" do
        create_jit_access_token

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "with an enqueued job" do
      let(:params) { { account: "org", repository: "repo" }.to_json }
      let(:update_job) { create(:update_job, :enqueued, hashed_token: hashed_token) }

      it "is a bad request" do
        create_jit_access_token

        expect(response).to have_http_status(:bad_request)
      end
    end

    context "with a processing job" do
      let(:params) { { account: "org", repository: "repo" }.to_json }
      let(:update_job) { create(:update_job, :processing, hashed_token: hashed_token) }

      it "is forbidden when the repo isn't found" do
        create_jit_access_token

        expect(response).to have_http_status(:forbidden)
      end

      # TODO: remove when we handle cross-org requests
      context "with an account other than the update job's" do
        let(:params) do
          { account: "another-account", repository: update_job.repo.name }.to_json
        end

        it "is forbidden when the account doesn't match the update job's account" do
          create_jit_access_token

          expect(response).to have_http_status(:forbidden)
        end
      end

      context "with a valid repo" do
        let(:other_repo) do
          FactoryBot.create(
            :repo,
            account: update_job.repo.account,
            name: "repo2",
          )
        end
        let(:params) do
          { account: update_job.repo.account.github_login, repository: other_repo.name }.to_json
        end

        it "returns the JIT credentials" do
          create_jit_access_token

          expect(response.body).to eq({ username: "x-access-token", password: new_token }.to_json)
          expect(response).to have_http_status(:ok)
        end
      end
    end
  end

  describe "POST /update_jobs/:id/create_pull_request" do
    subject(:create_pull_request) do
      post(
        "/update_jobs/#{update_job.id}/create_pull_request",
        headers: header,
        params: params,
      )
    end

    let(:header) do
      { "Content-Type" => "application/json", "Authorization" => external_job_token }
    end
    let(:update_job) do
      FactoryBot.create(
        :update_job, :processing,
        id: 1001,
        hashed_token: hashed_token,
      )
    end
    let(:github_access_token) do
      erb_fixture("github_responses/installation_access_token.json")
    end
    let(:github_url) { "https://api.github.com/" }
    let(:json_header) { { "Content-Type" => "application/json" } }
    let(:access_token_url_regex) do
      %r{#{Regexp.escape(github_url)}app/installations/[0-9]*/access_tokens}
    end
    let(:params) do
      {
        data: {
          dependencies: [
            {
              name: "business",
              version: "1.8.0",
              "previous-version": "1.7.0",
              requirements: [
                {
                  file: "Gemfile",
                  requirement: "~> 1.8.0",
                  groups: [],
                  source: nil,
                },
              ],
              "previous-requirements": [
                {
                  file: "Gemfile",
                  requirement: "~> 1.7.0",
                  groups: [],
                  source: nil,
                },
              ],
            },
          ],
          "updated-dependency-files": [
            {
              content: "some things",
              name: "Gemfile",
              directory: "/",
              type: "file",
            },
            {
              content: "more things",
              name: "Gemfile.lock",
              directory: "/",
              type: "file",
            },
          ],
          "base-commit-sha": "sha",
          "commit-message": "commit message",
          "pr-title": "pr title",
          "pr-body": "pr body",
        },
      }.to_json
    end

    before do
      FactoryBot.create(:pull_request, update_job: update_job)

      stub_request(:post, access_token_url_regex).
        to_return(status: 200, body: github_access_token, headers: json_header)
    end

    context "when a valid authorization header is provided" do
      it "returns no_content" do
        create_pull_request
        expect(response).to have_http_status(:no_content)
      end

      it "enqueues creating a pull request on GitHub" do
        expect do
          create_pull_request
        end.to have_enqueued_job(PrioritizedJobs::CreatePullRequestOnGitHub::Default).
          on_queue("create_pull_request_p2").
          with(pending_pr: instance_of(PendingPullRequest))
      end
    end

    context "when PR message data is not provided" do
      let(:params) do
        {
          data: {
            dependencies: [
              {
                name: "business",
                version: "1.8.0",
                "previous-version": "1.7.0",
                requirements: [
                  {
                    file: "Gemfile",
                    requirement: "~> 1.8.0",
                    groups: [],
                    source: nil,
                  },
                ],
                "previous-requirements": [
                  {
                    file: "Gemfile",
                    requirement: "~> 1.7.0",
                    groups: [],
                    source: nil,
                  },
                ],
              },
            ],
            "updated-dependency-files": [
              {
                content: "some things",
                name: "Gemfile",
                directory: "/",
                type: "file",
              },
              {
                content: "more things",
                name: "Gemfile.lock",
                directory: "/",
                type: "file",
              },
            ],
            "base-commit-sha": "sha",
          },
        }.to_json
      end

      it "returns bad_request" do
        create_pull_request
        expect(response).to have_http_status(:bad_request)
      end
    end

    context "when passing optional deleted and content_encoding attributes" do
      let(:params) do
        {
          data: {
            dependencies: [
              {
                name: "business",
                version: "1.8.0",
                "previous-version": "1.7.0",
                requirements: [
                  {
                    file: "Gemfile",
                    requirement: "~> 1.8.0",
                    groups: [],
                    source: nil,
                  },
                ],
                "previous-requirements": [
                  {
                    file: "Gemfile",
                    requirement: "~> 1.7.0",
                    groups: [],
                    source: nil,
                  },
                ],
              },
            ],
            "updated-dependency-files": [
              {
                content: "some things",
                name: "Gemfile",
                directory: "/",
                type: "file",
                content_encoding: "utf-8",
                deleted: false,
              },
              {
                content: "more things",
                name: "Gemfile.lock",
                directory: "/",
                type: "file",
                content_encoding: "utf-8",
                deleted: false,
              },
            ],
            "base-commit-sha": "sha",
            "commit-message": "commit message",
            "pr-title": "pr title",
            "pr-body": "pr body",
          },
        }.to_json
      end

      it "persists the updated_dependency_files on the pending pull request" do
        create_pull_request
        expect(PendingPullRequest.last.updated_dependency_files).
          to eq([
                  Dependabot::DependencyFile.new(
                    content: "some things",
                    name: "Gemfile",
                    directory: "/",
                    type: "file",
                    content_encoding: "utf-8",
                    deleted: false,
                  ),
                  Dependabot::DependencyFile.new(
                    content: "more things",
                    name: "Gemfile.lock",
                    directory: "/",
                    type: "file",
                    content_encoding: "utf-8",
                    deleted: false,
                  ),
                ])
      end
    end
  end

  describe "POST /update_jobs/:id/update_pull_request" do
    subject(:update_pull_request) do
      post(
        "/update_jobs/#{update_job.id}/update_pull_request",
        headers: header,
        params: params,
      )
    end

    let(:header) do
      { "Content-Type" => "application/json", "Authorization" => external_job_token }
    end
    let(:github_access_token) do
      erb_fixture("github_responses/installation_access_token.json")
    end
    let(:github_url) { "https://api.github.com/" }
    let(:json_header) { { "Content-Type" => "application/json" } }
    let(:access_token_url_regex) do
      %r{#{Regexp.escape(github_url)}app/installations/[0-9]*/access_tokens}
    end
    let(:params) do
      {
        data: {
          "dependency-names": ["business"],
          "updated-dependency-files": [
            {
              content: "some things",
              name: "Gemfile",
              directory: "/",
              type: "file",
            },
            {
              content: "more things",
              name: "Gemfile.lock",
              directory: "/",
              type: "file",
            },
          ],
          "base-commit-sha": "sha",
        },
      }.to_json
    end

    before do
      stub_request(:post, access_token_url_regex).
        to_return(status: 200, body: github_access_token, headers: json_header)
    end

    context "when a valid authorization header is provided" do
      context "and the update job was for a specific dependency" do
        let(:update_config) { FactoryBot.create(:update_config) }
        let(:old_update_job) do
          FactoryBot.create(
            :update_job,
            update_config: update_config,
          )
        end
        let!(:pull_request) do
          FactoryBot.create(
            :pull_request, :updating,
            update_job: old_update_job,
            dependencies: [{ name: "business", version: "1.8.0" }],
          )
        end
        let(:update_job) do
          update_job = pull_request.last_transition.update_job
          update_job.transition_to!(:enqueued)
          update_job.transition_to!(:processing)
          update_job.update!(
            hashed_token: hashed_token,
          )
          update_job
        end

        it "returns no_content" do
          update_pull_request
          expect(response).to have_http_status(:no_content)
        end

        it "enqueues updating the pull request on GitHub" do
          expect(UpdatePullRequestJob).to receive(:perform_later)
          update_pull_request
        end

        context "when passing optional deleted and encoding attributes" do
          let(:params) do
            {
              data: {
                "dependency-names": ["business"],
                "updated-dependency-files": [
                  {
                    content: "some things",
                    name: "Gemfile",
                    directory: "/",
                    type: "file",
                    content_encoding: "utf-8",
                    deleted: false,
                  },
                  {
                    content: "more things",
                    name: "Gemfile.lock",
                    directory: "/",
                    type: "file",
                    content_encoding: "utf-8",
                    deleted: false,
                  },
                ],
                "base-commit-sha": "sha",
              },
            }.to_json
          end

          it "persists the updated_dependency_files on the pending pr update" do
            update_pull_request
            expect(PendingPullRequestUpdate.last.updated_dependency_files).
              to eq([
                      Dependabot::DependencyFile.new(
                        content: "some things",
                        name: "Gemfile",
                        directory: "/",
                        type: "file",
                        content_encoding: "utf-8",
                        deleted: false,
                      ),
                      Dependabot::DependencyFile.new(
                        content: "more things",
                        name: "Gemfile.lock",
                        directory: "/",
                        type: "file",
                        content_encoding: "utf-8",
                        deleted: false,
                      ),
                    ])
          end
        end
      end
    end
  end

  describe "POST /update_jobs/:id/close_pull_request" do
    subject(:close_pull_request) do
      post(
        "/update_jobs/#{update_job.id}/close_pull_request",
        headers: header,
        params: params,
      )
    end

    let(:header) do
      { "Content-Type" => "application/json", "Authorization" => external_job_token }
    end
    let(:params) do
      {
        data: {
          "dependency-names": ["business"],
          "reason" => "dependency_removed",
        },
      }.to_json
    end

    context "when a valid authorization header is provided" do
      context "and the update job was for a specific dependency" do
        let(:update_config) { FactoryBot.create(:update_config) }
        let(:old_update_job) do
          FactoryBot.create(
            :update_job,
            update_config: update_config,
          )
        end
        let!(:pull_request) do
          FactoryBot.create(
            :pull_request, :updating,
            update_job: old_update_job,
            dependencies: [{ name: "business", version: "1.8.0" }],
          )
        end
        let(:update_job) do
          update_job = pull_request.last_transition.update_job
          update_job.transition_to!(:enqueued)
          update_job.transition_to!(:processing)
          update_job.update!(
            hashed_token: hashed_token,
          )
          update_job
        end

        it "returns no_content" do
          close_pull_request
          expect(response).to have_http_status(:no_content)
        end

        it "enqueues a job to close the pull request" do
          expect { close_pull_request }.
            to have_enqueued_job(ClosePullRequestJob)
        end
      end
    end
  end

  describe "POST /update_jobs/:id/update_dependency_list" do
    subject(:update_dependency_list) do
      post(
        "/update_jobs/#{update_job.id}/update_dependency_list",
        headers: header,
        params: params
      )
    end

    let(:header) do
      { "Content-Type" => "application/json", "Authorization" => external_job_token }
    end
    let(:update_job) do
      FactoryBot.create(
        :update_job, :processing,
        hashed_token: hashed_token,
      )
    end
    let(:params) do
      { data: { dependency_files: ["Gemfile", "Gemfile.lock"] } }.to_json
    end

    it "updates the monitored_files" do
      expect { update_dependency_list }.
        to change { update_job.update_config.reload.monitored_files }.
        from(nil).to(["Gemfile", "Gemfile.lock"])
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "POST /update_jobs/:id/record_update_job_error" do
    subject(:record_update_job_error) do
      post(
        "/update_jobs/#{update_job.id}/record_update_job_error",
        params: params,
        headers: header,
      )
    end

    let(:header) do
      { "Content-Type" => "application/json", "Authorization" => external_job_token }
    end
    let(:update_job) do
      FactoryBot.create(
        :update_job, :processing,
        hashed_token: hashed_token,
      )
    end
    let(:json_header) { { "Content-Type" => "application/json" } }
    let(:github_url) { "https://api.github.com/" }
    let(:repo_url) do
      github_url + "repositories/#{update_job.update_config.repo.github_id}"
    end
    let(:github_access_token) do
      erb_fixture("github_responses/installation_access_token.json")
    end
    let(:access_token_url_regex) do
      %r{#{Regexp.escape(github_url)}app/installations/[0-9]*/access_tokens}
    end

    let(:params) { { data: error }.to_json }
    let(:error) do
      { "error-type" => error_type, "error-details" => error_detail }
    end
    let(:error_type) { "dependency_file_not_evaluatable" }
    let(:error_detail) { { "message" => "My message" } }

    before do
      stub_request(:post, access_token_url_regex).
        to_return(status: 200, body: github_access_token, headers: json_header)
    end

    context "when a valid authorization header is provided" do
      let(:github_issue) { fixture("github_responses/issue.json") }
      let(:github_repo) { fixture("github_responses/repo.json") }

      before do
        stub_request(:get, repo_url).
          to_return(status: 200, body: github_repo, headers: json_header)
        stub_request(:post, repo_url + "/issues").
          to_return(status: 200, body: github_issue, headers: json_header)
      end

      it "creates an update job error" do
        expect { record_update_job_error }.
          to change(UpdateJobError, :count).by(1)
        expect(response).to have_http_status(:no_content)
      end
    end

    context "when extra metadata is included in the details" do
      let(:error_detail) do
        { "message" => "My message", "extra-metadata": { "some-extra-field" => "some-extra-value" } }
      end

      it "ignores the extra metadata" do
        expect { record_update_job_error }.
          to change(UpdateJobError, :count).by(1)
        expect(response).to have_http_status(:no_content)
      end
    end
  end

  describe "POST /update_jobs/:id/record_update_job_unknown_error", :cloud do
    subject(:record_update_job_unknown_error) do
      post(
        "/update_jobs/#{update_job.id}/record_update_job_unknown_error",
        params: params,
        headers: header,
      )
    end

    let(:header) do
      { "Content-Type" => "application/json", "Authorization" => external_job_token }
    end
    let(:update_job) do
      FactoryBot.create(
        :update_job, :processing,
        hashed_token: hashed_token,
      )
    end
    let(:json_header) { { "Content-Type" => "application/json" } }
    let(:github_url) { "https://api.github.com/" }
    let(:repo_url) do
      github_url + "repositories/#{update_job.update_config.repo.github_id}"
    end
    let(:github_access_token) do
      erb_fixture("github_responses/installation_access_token.json")
    end
    let(:access_token_url_regex) do
      %r{#{Regexp.escape(github_url)}app/installations/[0-9]*/access_tokens}
    end

    let(:params) { { data: error }.to_json }
    let(:error) do
      { "error-type" => error_type, "error-details" => error_detail }
    end
    let(:error_type) { "server_error" }
    let(:error_detail) { { "message" => "My message" } }

    before do
      allow(Dependabot::Exceptions).to receive(:report).with(be_a(UpdaterError), be_a(Hash))
      stub_request(:post, access_token_url_regex).
        to_return(status: 200, body: github_access_token, headers: json_header)
    end

    context "when a valid authorization header is provided" do
      let(:github_issue) { fixture("github_responses/issue.json") }
      let(:github_repo) { fixture("github_responses/repo.json") }

      before do
        stub_request(:get, repo_url).
          to_return(status: 200, body: github_repo, headers: json_header)
        stub_request(:post, repo_url + "/issues").
          to_return(status: 200, body: github_issue, headers: json_header)
      end

      it "creates an update job unknown error" do
        expect { record_update_job_unknown_error }.
          to change(UpdateJobUnknownError, :count).by(1)
        expect(response).to have_http_status(:no_content)
      end
    end
  end

  describe "POST /update_jobs/:id/record_ecosystem_versions" do
    subject(:record_ecosystem_versions) do
      post(
        "/update_jobs/#{update_job.id}/record_ecosystem_versions",
        params: params,
        headers: header,
      )
    end

    let(:header) do
      { "Content-Type" => "application/json", "Authorization" => external_job_token }
    end
    let(:update_job) do
      FactoryBot.create(
        :update_job, :processing,
        hashed_token: hashed_token,
      )
    end
    let(:json_header) { { "Content-Type" => "application/json" } }

    let(:params) do
      { data: { "ecosystem_versions" => { "ruby" => { "min" => 3, "max" => 3.2 } } } }.to_json
    end

    context "when a valid authorization header is provided" do
      it "records the ecosystem versions" do
        record_ecosystem_versions

        expect(response).to have_http_status(:no_content)
        expect(update_job.reload.metrics_metadata["ecosystem_versions"]).to eq(
          { "ruby" => { "min" => 3, "max" => 3.2 } }
        )
      end
    end
  end

  describe "POST /update_jobs/:id/increment_metric" do
    subject(:increment_metric) do
      post(
        "/update_jobs/#{update_job.id}/increment_metric",
        params: params,
        headers: header,
      )
    end

    let(:header) do
      { "Content-Type" => "application/json", "Authorization" => external_job_token }
    end
    let(:json_header) { { "Content-Type" => "application/json" } }

    context "with no job matching the provided token" do
      let(:update_job) do
        FactoryBot.create(
          :update_job, :processing,
          hashed_token: "no-match",
        )
      end

      let(:params) do
        { data: { metric: "foo", "tags" => { "bar" => "baz" } } }.to_json
      end

      it "is forbidden" do
        increment_metric

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "with an enqueued job" do
      let(:params) do
        { data: { metric: "foo", "tags" => { "bar" => "baz" } } }.to_json
      end

      let(:update_job) do
        FactoryBot.create(
          :update_job, :enqueued,
          hashed_token: hashed_token,
        )
      end

      it "is a bad request" do
        increment_metric

        expect(response).to have_http_status(:bad_request)
      end
    end

    context "with a processing job" do
      let(:params) do
        { data: { metric: "foo", "tags" => { "bar" => "baz" } } }.to_json
      end

      let(:update_job) do
        FactoryBot.create(
          :update_job, :processing,
          hashed_token: hashed_token,
        )
      end

      it "is a successful request" do
        increment_metric

        expect(response).to have_http_status(:no_content)
      end
    end

    context "with a processing job and invalid parameters" do
      let(:params) do
        { data: { increment: "foo", "tags" => { "bar" => "baz" } } }.to_json
      end

      let(:update_job) do
        FactoryBot.create(
          :update_job, :processing,
          hashed_token: hashed_token,
        )
      end

      it "is a bad request" do
        increment_metric

        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe "POST /update_jobs/:id/record_metrics" do
    subject(:record_metrics) do
      post(
        "/update_jobs/#{update_job.id}/record_metrics",
        params: params,
        headers: header,
      )
    end

    let(:header) do
      { "Content-Type" => "application/json", "Authorization" => external_job_token }
    end
    let(:json_header) { { "Content-Type" => "application/json" } }

    context "with no job matching the provided token" do
      let(:update_job) do
        FactoryBot.create(
          :update_job, :processing,
          hashed_token: "no-match",
        )
      end

      let(:params) do
        { data: { metric: "foo", type: "increment", "tags" => { "bar" => "baz" } } }.to_json
      end

      it "is forbidden" do
        record_metrics

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "with an enqueued job" do
      let(:params) do
        { data: { metric: "foo", type: "increment", "tags" => { "bar" => "baz" } } }.to_json
      end

      let(:update_job) do
        FactoryBot.create(
          :update_job, :enqueued,
          hashed_token: hashed_token,
        )
      end

      it "is a bad request" do
        record_metrics

        expect(response).to have_http_status(:bad_request)
      end
    end

    context "with a processing job" do
      let(:params) do
        {
          data: [
            { metric: "updater.started", type: "increment", value: 1, tags: { operation: "baz" } },
          ],
        }.to_json
      end

      let(:update_job) do
        FactoryBot.create(
          :update_job, :processing,
          hashed_token: hashed_token,
        )
      end

      it "is a successful request" do
        record_metrics

        expect(response).to have_http_status(:no_content)
      end
    end

    context "with a processing job and invalid parameters" do
      let(:params) do
        { data: { increment: "foo", "tags" => { "bar" => "baz" } } }.to_json
      end

      let(:update_job) do
        FactoryBot.create(
          :update_job, :processing,
          hashed_token: hashed_token,
        )
      end

      it "is a bad request" do
        record_metrics

        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe "POST /update_jobs/:id/record_ecosystem_meta" do
    subject(:ecosystem_meta) do
      post(
        "/update_jobs/#{update_job.id}/record_ecosystem_meta",
        params: params,
        headers: header,
      )
    end

    let(:header) do
      { "Content-Type" => "application/json", "Authorization" => external_job_token }
    end

    let(:params) do
      {
        data: [
          {
            "ecosystem": {
              "name": "npm_and_yarn",
              "package_manager": {
                "name": "npm",
                "raw_version": "2.5.1-alpha",
                "version": "2.5.1",
                "requirement": {
                  "raw_constraint": ">= 2.0",
                  "min_raw_version": "2.0.0-alpha",
                  "min_version": "2.0.0",
                  "max_raw_version": "3.0.0-beta",
                  "max_version": "3.0.0",
                },
              },
              "language": {
                "name": "node",
                "raw_version": "3.5.2-beta",
                "version": "3.5.2",
                "requirement": {
                  "raw_constraint": ">= 2.5",
                  "min_raw_version": "2.5.0-alpha",
                  "min_version": "2.5.0",
                  "max_raw_version": "3.2.0-beta",
                  "max_version": "3.2.0",
                },
              },
            },
          },
        ],
      }.to_json
    end

    let(:json_header) { { "Content-Type" => "application/json" } }

    context "with an enqueued job" do
      let(:update_job) do
        FactoryBot.create(
          :update_job, :enqueued,
          hashed_token: hashed_token,
        )
      end

      it "is a bad request" do
        ecosystem_meta

        expect(response).to have_http_status(:bad_request)
      end
    end

    context "with a processing job" do
      let(:update_job) do
        FactoryBot.create(
          :update_job, :processing,
          hashed_token: hashed_token,
        )
      end

      it "is a successful request" do
        ecosystem_meta

        expect(response).to have_http_status(:no_content)
      end
    end

    context "with a processing job and invalid parameters" do
      let(:params) { { data: [] }.to_json }

      let(:update_job) do
        FactoryBot.create(
          :update_job, :processing,
          hashed_token: hashed_token,
        )
      end

      it "is a bad request" do
        ecosystem_meta

        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe "POST /update_jobs/:id/record_cooldown_meta" do
    subject(:cooldown_meta) do
      post(
        "/update_jobs/#{update_job.id}/record_cooldown_meta",
        params: params,
        headers: header,
      )
    end

    let(:header) do
      { "Content-Type" => "application/json", "Authorization" => external_job_token }
    end

    let(:params) do
      {
        data: [
          {
            "cooldown": {
              "ecosystem_name": "docker",
              "config": {
                "default_days": "90",
                "semver_major_days": "7",
                "semver_minor_days": "7",
                "semver_patch_days": "7",
              },
            },
          },
        ],
      }.to_json
    end

    let(:json_header) { { "Content-Type" => "application/json" } }

    context "with an enqueued job" do
      let(:update_job) do
        FactoryBot.create(
          :update_job, :enqueued,
          hashed_token: hashed_token,
        )
      end

      it "is a bad request" do
        cooldown_meta

        expect(response).to have_http_status(:bad_request)
      end
    end

    context "with a processing job" do
      let(:update_job) do
        FactoryBot.create(
          :update_job, :processing,
          hashed_token: hashed_token,
        )
      end

      it "is a successful request" do
        cooldown_meta

        expect(response).to have_http_status(:no_content)
      end
    end

    context "with a processing job and invalid parameters" do
      let(:params) { { data: [] }.to_json }

      let(:update_job) do
        FactoryBot.create(
          :update_job, :processing,
          hashed_token: hashed_token,
        )
      end

      it "is a bad request" do
        cooldown_meta

        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe "PATCH /update_jobs/:id/mark_as_processed" do
    subject(:mark_as_processed) do
      patch(
        "/update_jobs/#{update_job.id}/mark_as_processed",
        params: params,
        headers: header,
      )
    end

    let(:header) do
      { "Content-Type" => "application/json", "Authorization" => external_job_token }
    end
    let(:update_job) do
      FactoryBot.create(
        :update_job, :processing,
        hashed_token: hashed_token,
      )
    end
    let(:json_header) { { "Content-Type" => "application/json" } }
    let(:github_url) { "https://api.github.com/" }
    let(:repo_url) do
      github_url + "repositories/#{update_job.update_config.repo.github_id}"
    end
    let(:github_access_token) do
      erb_fixture("github_responses/installation_access_token.json")
    end
    let(:access_token_url_regex) do
      %r{#{Regexp.escape(github_url)}app/installations/[0-9]*/access_tokens}
    end

    let(:params) do
      { data: { "base-commit-sha": "sha" } }.to_json
    end

    before do
      FactoryBot.create(:pending_pull_request, update_job: update_job)

      stub_request(:post, access_token_url_regex).
        to_return(status: 200, body: github_access_token, headers: json_header)
    end

    context "when a valid authorization header is provided" do
      it "marks the update job as processed" do
        expect { mark_as_processed }.
          to change { update_job.reload.current_state }.
          from("processing").to("processed")
        expect(response).to have_http_status(:no_content)
      end
    end

    context "when there were errors" do
      before do
        FactoryBot.create(
          :update_job_error,
          update_job: update_job,
          error_type: error_type,
          error_details: error_detail,
        )
      end

      context "with a new error" do
        let(:error_type) { "dependency_file_not_evaluatable" }
        let(:error_detail) { nil }
        let(:github_issue) { fixture("github_responses/issue.json") }
        let(:github_repo) { fixture("github_responses/repo.json") }

        before do
          stub_request(:get, repo_url).
            to_return(status: 200, body: github_repo, headers: json_header)
          stub_request(:post, repo_url + "/issues").
            to_return(status: 200, body: github_issue, headers: json_header)
        end

        it "marks the job as processed with errors" do
          expect { mark_as_processed }.
            to change { update_job.reload.current_state }.
            from("processing").to("processed_with_errors")
          expect(response).to have_http_status(:no_content)
        end

        it "enqueues creating an error to inform the user" do
          expect { mark_as_processed }.to have_enqueued_job(NotifyGitHubOfFailureJob)
        end
      end
    end
  end
end
