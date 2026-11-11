# frozen_string_literal: true

require "rails_helper"

RSpec.describe PrioritizedJobs::CreatePullRequestOnGitHub::Default do
  include ActiveJob::TestHelper
  include GitHub::Twirp::DependabotPullRequests::Helpers

  subject(:job) { described_class.new(pending_pr: pending_pr) }

  def perform_later
    described_class.perform_later(pending_pr: pending_pr)
  end

  def encrypt_temporary_file_blob(blob)
    token = Base64.strict_decode64(Prius.get(:temporary_file_encryption_key))
    encrypted_box = RbNaCl::SimpleBox.from_secret_key(token)

    Base64.strict_encode64(encrypted_box.encrypt(blob))
  end

  def create_previous_pull_request
    previous_update_job = create(:update_job, update_config: update_config)
    create(
      :pull_request,
      repo: repo,
      update_job: previous_update_job,
      dependencies: [updated_dependency_hash.merge("version" => old_version)],
      github_number: 21,
      head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
      dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
    )
  end

  let(:pending_pr) do
    pr = PendingPullRequest.create!(
      update_job: update_job,
      updated_dependency_details: updated_dependency_details,
      sort_key: 0,
    )
    pr.encrypted_dependency_files_blob.attach(
      io: StringIO.new(encrypt_temporary_file_blob(files.to_json)),
      filename: pr.id,
      content_type: "application/octet-stream",
      identify: false,
    )
    pr.message_data = message_data
    pr
  end
  let(:account) { create(:account, :dependabot, :active) }
  let(:repo) { create(:repo, :bump_test, account: account) }
  let(:update_config) do
    create(:update_config, :rate_limited,
           repo: repo,
           package_manager: "bundler",
           open_pull_requests_limit:)
  end
  let(:open_pull_requests_limit) { UpdateConfig::DEFAULT_OPEN_PULL_REQUESTS_LIMIT }
  let(:sha) { "0123456789012345678901234567890123456789" }
  let(:update_job) { create(:update_job, update_config: update_config, github_request_id: nil, base_commit_sha: sha) }
  let(:updated_dependency_details) { [updated_dependency_hash] }
  let(:updated_dependency_hash) do
    {
      "name" => name,
      "version" => version,
      "previous_version" => previous_version,
      "requirements" => requirements,
      "previous_requirements" => previous_requirements,
      "package_manager" => "bundler",
    }
  end
  let(:name) { "business" }
  let(:version) { "1.8.0" }
  let(:old_version) { "1.7.1" }
  let(:previous_version) { "1.7.0" }
  let(:requirements) do
    [{ file: "Gemfile", requirement: "~> 1.8.0", groups: [], source: nil }]
  end
  let(:previous_requirements) do
    [{ file: "Gemfile", requirement: "~> 1.7.0", groups: [], source: nil }]
  end
  let(:files) do
    [
      {
        "content" => "things1",
        "name" => "Gemfile",
        "directory" => "/test",
        "type" => "file",
        "operation" => "update",
        "support_file" => false,
        "content_encoding" => "utf-8",
        "deleted" => false,
      },
      {
        "content" => "things2",
        "name" => "Gemfile.lock",
        "directory" => "/test",
        "type" => "file",
        "operation" => "update",
        "support_file" => false,
        "content_encoding" => "utf-8",
        "deleted" => false,
      },
    ]
  end
  let(:message_data) do
    {
      commit_message: "some commit message",
      pr_title: "some pr title",
      pr_body: "some pr body",
    }
  end
  let(:branch_name) { "dependabot/bundler/test/business-1.8.0" }

  let(:pr_service) do
    instance_double(GitHub::Twirp::DependabotPullRequests)
  end

  let(:repo_synchronizer_result) do
    SynchronizeRepoState::SynchronizeRepoStateResult.error(
      reason: SynchronizeRepoState::ACCOUNT_OUT_OF_SYNC
    )
  end
  let(:repo_synchronizer) { instance_double(SynchronizeRepoState, run: repo_synchronizer_result) }

  let(:commit_sha) { "0123456789012345678901234567890123456789" }
  let(:pr_number) { 129837128937 }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:repo_url) { github_url + "repositories/#{repo.github_id}/" }

  before do
    allow(GitHub::Twirp::DependabotPullRequests).to receive(:new).and_return(pr_service)
    allow(SynchronizeRepoState).
      to receive(:new).with(repo: repo, event_source: anything).
      and_return(repo_synchronizer)

    allow(GitHubHelpers).to receive(:access_token_for)
    stub_request(:get, repo_url + "pulls?per_page=100&state=open").
      and_return(body: [].to_json, headers: json_header)

    allow(pr_service).to receive_messages(
      get_pull_requests: [],
      check_pull_request_eligibility: described_class::EligibilityResult::RESULT_OK,
      publish_changes: MonolithTwirp::Dependabot::PullRequests::V1::PublishChangesResponse.new(
        commit_sha: commit_sha,
        repository_id: update_config.repo.github_id,
        branch_name: branch_name,
      ),
      create_pull_request: MonolithTwirp::Dependabot::PullRequests::V1::PullRequest.new(
        github_number: pr_number,
        repository_id: update_config.repo.github_id,
        state: "open",
        has_user_commits: false,
        head_sha: "a" * 40,
        base_sha: "b" * 40,
      )
    )
    allow(update_job).to receive(:increment_metric)
  end

  it "locks PR creation using Restraints.for_branch_changes" do
    # reassign to local var to avoid clashing variable names
    expected_branch_name = branch_name
    expected_repo = repo
    expect(Restraints).to receive(:for_branch_changes) do |repo:, branch_name:, &block|
      expect(expected_repo).to eq(repo)
      expect(branch_name).to eq(expected_branch_name)
      expect(block).not_to be_nil
      raise Restraint::UnableToLock, "key"
    end

    expect { job.perform_now }.to have_enqueued_job(described_class)
  end

  it "throttles PR creation using the pull_request throttler" do
    expect(Throttlers.pull_request).to receive(:throttle)
    job.perform_now
  end

  it "includes tenant information in client requests", :proxima do
    job.perform_now

    expect(GitHub::Twirp::DependabotPullRequests).to have_received(:new).
      with(
        client: Dependabot::Application.github_twirp_client,
        tenant: update_config.account.tenant
      )
  end

  it "adds pending PR and update job telemetry to logging calls" do
    allow(Dependabot::Logger).to receive(:log_context).and_call_original
    # Raise an error to trigger rescue_from
    allow(pr_service).to receive(:publish_changes).and_raise(StandardError)
    expect { job.perform_now }.to raise_error(StandardError)

    # The pending PR's telemetry attributes are added to logger context
    # only in the job's perform.
    expect(Dependabot::Logger).to have_received(:log_context).with(pending_pr.telemetry_attributes).once
  end

  context "when the pending pull request model cannot create a new PR" do
    before do
      allow(pending_pr).to receive(:can_create_pull_request?).and_return(false)
    end

    it "logs an update job error" do
      expect { job.perform_now }.
        to change { update_job.update_job_errors.count }.
        from(0).to(1)
      expect(update_job.update_job_errors.first.error_type).
        to eq("pull_request_creation_halted")
    end

    it "does not cause the job to raise an error" do
      expect { job.perform_now }.not_to raise_error
    end
  end

  context "with a new pending PR" do
    it "creates the PR on GitHub" do # rubocop:disable RSpec/ExampleLength
      expect { job.perform_now }.to have_enqueued_job(CreatePullRequestOnDependabot).with(
        pending_pr: pending_pr,
        github_pull_request: hash_including(
          github_number: pr_number,
          repository_id: update_config.repo.github_id,
          head_sha: "a" * 40,
          base_sha: "b" * 40,
          state: "open",
          has_user_commits: false,
        ),
      )

      expect(pr_service).to have_received(:publish_changes).once do |payload, _options|
        expect(payload).to eq(
          repo: update_config.repo,
          dependabot_branch_name: branch_name,
          base_commit_sha: update_job.base_commit_sha,
          dependency_files: [
            Dependabot::DependencyFile.new(
              name: "Gemfile",
              content: "things1",
              directory: "/test",
              support_file: false,
              deleted: false,
              content_encoding: "utf-8",
              type: "file",
            ),
            Dependabot::DependencyFile.new(
              name: "Gemfile.lock",
              content: "things2",
              directory: "/test",
              support_file: false,
              deleted: false,
              content_encoding: "utf-8",
              type: "file",
            ),
          ],
          commit_message: <<~MESSAGE.strip,
            some commit message

            ---
            updated-dependencies:
            - dependency-name: business
              dependency-version: 1.8.0
              dependency-type: direct:production
              update-type: version-update:semver-minor
            ...

            Signed-off-by: dependabot[bot] <support@github.com>
          MESSAGE
        )
      end

      expect(pr_service).to have_received(:create_pull_request).once do |args|
        expect(args[:repo]).to eq(update_config.repo)
        expect(args[:base_branch_name]).to eq(update_config.target_branch)
        expect(args[:head_branch_name]).to eq(branch_name)
        expect(args[:pr_name]).to eq("some pr title")
        expect(args[:labels]).to eq(
          [
            MonolithTwirp::Dependabot::PullRequests::V1::Label.new(
              name: "dependencies",
              color: "0366d6",
              description: "Pull requests that update a dependency file"
            ),
            MonolithTwirp::Dependabot::PullRequests::V1::Label.new(
              name: "ruby",
              color: "ce2d2d",
              description: "Pull requests that update ruby code"
            ),
            MonolithTwirp::Dependabot::PullRequests::V1::Label.new(
              name: "minor",
            ),
          ]
        )
        expect(args[:reviewers]).to eq({ "reviewers" => [], "team_reviewers" => [] })
        expect(args[:assignees]).to eq(update_job.default_assignees.to_a)
        expect(args[:milestone_number]).to eq(update_job.default_milestone)
        compatibility_message = if Dependabot.proxima? || Dependabot.enterprise?
                                  ""
                                else
                                  "[![Dependabot compatibility score](https://dependabot-badges.githubapp.com/badges/compatibility_score?dependency-name=business&package-manager=bundler&previous-version=1.7.0&new-version=1.8.0)](https://docs.github.com/en/github/managing-security-vulnerabilities/about-dependabot-security-updates#about-compatibility-scores)\n\n"
                                end
        expect(args[:pr_description]).to eq(<<~DESCRIPTION.strip)
          some pr body

          #{compatibility_message}Dependabot will resolve any conflicts with this PR as long as you don't alter it yourself. You can also trigger a rebase manually by commenting `@dependabot rebase`.

          [//]: # (dependabot-automerge-start)
          [//]: # (dependabot-automerge-end)

          ---

          <details>
          <summary>Dependabot commands and options</summary>
          <br />

          You can trigger Dependabot actions by commenting on this PR:
          - `@dependabot rebase` will rebase this PR
          - `@dependabot recreate` will recreate this PR, overwriting any edits that have been made to it
          - `@dependabot show <dependency name> ignore conditions` will show all of the ignore conditions of the specified dependency
          - `@dependabot ignore this major version` will close this PR and stop Dependabot creating any more for this major version (unless you reopen the PR or upgrade to it yourself)
          - `@dependabot ignore this minor version` will close this PR and stop Dependabot creating any more for this minor version (unless you reopen the PR or upgrade to it yourself)
          - `@dependabot ignore this dependency` will close this PR and stop Dependabot creating any more for this dependency (unless you reopen the PR or upgrade to it yourself)


          </details>
        DESCRIPTION

        expect(update_job).to have_received(:increment_metric).
          with("create_pull_request.attempt", { tags: { grouped_update: false, v2: true } }).once
        expect(update_job).to have_received(:increment_metric).
          with("create_pull_request.success", { tags: { grouped_update: false, v2: true } }).once
      end
    end
  end

  context "when the pending pull request is a grouped update" do
    let(:dependency_group) { create(:dependency_group, name: "my-deps") }

    before do
      pending_pr.update!(dependency_group: dependency_group, grouped_update: true)
    end

    it "creates a new pull request" do
      expect { job.perform_now }.to have_enqueued_job(CreatePullRequestOnDependabot)
      expect(pr_service).to have_received(:create_pull_request)
    end
  end

  shared_context "with multi-ecosystem update setup" do
    let(:dependency_group) { create(:dependency_group, name: "my-deps") }
    let(:multi_ecosystem_config_id) { 1 }
    let(:enqueue_scheduled_update_id) { "aaa" }
    let(:update_config) do
      create(:update_config, :rate_limited,
             repo: repo,
             package_manager: "bundler",
             default_assignees: ["alice"],
             multi_ecosystem_config_id: multi_ecosystem_config_id,
             open_pull_requests_limit: open_pull_requests_limit)
    end
    let(:update_job) do
      create(:update_job,
             update_config: update_config,
             github_request_id: nil,
             base_commit_sha: sha,
             enqueue_scheduled_update_id: enqueue_scheduled_update_id)
    end

    before do
      update_config2 = create(:update_config, :rate_limited,
                              repo: repo,
                              package_manager: "npm_and_yarn",
                              multi_ecosystem_config_id: multi_ecosystem_config_id,
                              default_assignees: ["bob"],
                              open_pull_requests_limit: open_pull_requests_limit)
      update_job2 = create(:update_job,
                           update_config: update_config2,
                           github_request_id: nil,
                           base_commit_sha: sha,
                           enqueue_scheduled_update_id: enqueue_scheduled_update_id)
      create(:pending_pull_request, update_job: update_job2)
      pending_pr.update!(dependency_group: dependency_group, grouped_update: true)
    end
  end

  context "when the pending pull request is multi-ecosystem update" do
    include_context "with multi-ecosystem update setup"

    it "creates a new pull request with combined labels" do # rubocop:disable RSpec/ExampleLength
      expect { job.perform_now }.to have_enqueued_job(CreatePullRequestOnDependabot)
      expect(pr_service).to have_received(:create_pull_request).once do |args|
        expect(args[:labels]).to eq(
          [
            MonolithTwirp::Dependabot::PullRequests::V1::Label.new(
              name: "dependencies",
              color: "0366d6",
              description: "Pull requests that update a dependency file"
            ),
            MonolithTwirp::Dependabot::PullRequests::V1::Label.new(
              name: "ruby",
              color: "ce2d2d",
              description: "Pull requests that update ruby code"
            ),
            MonolithTwirp::Dependabot::PullRequests::V1::Label.new(
              name: "minor",
            ),
            MonolithTwirp::Dependabot::PullRequests::V1::Label.new(
              name: "javascript",
              color: "168700",
              description: "Pull requests that update javascript code"
            ),
          ]
        )
      end
    end
  end

  context "multi-ecosystem reviewers and assignees" do
    include_context "with multi-ecosystem update setup"

    it "returns a merged list of reviewers and assignees" do
      job.perform_now
      expect(pr_service).to have_received(:create_pull_request).once do |args|
        expect(args[:reviewers]).to eq({
                                         "reviewers" => [],
                                         "team_reviewers" => [],
                                       })

        expect(args[:assignees]).to eq(%w(alice bob))
      end
    end
  end

  context "when an existing pull request is found" do
    let(:existing_pull_request) { instance_double(PullRequest, github_number: 123) }

    before do
      allow(PrioritizedJobs::CreatePullRequestOnGitHub::Lib::PullRequestQuery).to receive(:new).and_return(
        instance_double(
          PrioritizedJobs::CreatePullRequestOnGitHub::Lib::PullRequestQuery,
          existing_pull_request: existing_pull_request
        )
      )
    end

    it "logs the existing pull request and does not create a new one" do
      allow(Dependabot::Logger).to receive(:info)
      allow(update_job).to receive(:increment_metric)
      allow(pr_service).to receive(:publish_changes)

      job.perform_now

      expect(pr_service).not_to have_received(:publish_changes)
      expect(Dependabot::Logger).to have_received(:info).with(
        "PR already exists: ##{existing_pull_request.github_number}"
      )
      expect(update_job).to have_received(:increment_metric).with(
        "create_pull_request.existing", tags: { grouped_update: false, v2: true }
      )
    end
  end

  context "when a PullRequest which is pending exists, but no open PRs exist" do
    it "does not look up information for the pending PullRequest" do
      allow(pr_service).to receive(:get_pull_requests)

      previous_update_job = create(:update_job, update_config: update_config)
      previous_pull_request =
        create(:pull_request,
               repo: repo,
               update_job: previous_update_job,
               dependencies: [updated_dependency_hash.merge("version" => old_version)],
               github_number: nil,
               head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
               dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",)
      previous_pull_request.transition_to(:pending)

      job.perform_now

      expect(pr_service).not_to have_received(:get_pull_requests)
    end
  end

  context "with open Pull Requests on GitHub" do
    before do
      previous_update_job = create(:update_job, update_config: update_config)

      [21, 22, 23].each do |github_number|
        create(
          :pull_request,
          repo: repo,
          update_job: previous_update_job,
          dependencies: [
            {
              "name" => "unrelated_dep",
              "version" => "1.8.0",
              "previous_version" => "1.3.0",
              "requirements" => [],
              "previous_requirements" => [],
            },
          ],
          github_number: github_number,
        )
      end

      prs_body = fixture("github_responses/pull_requests_multiple.json")
      stub_request(:get, repo_url + "pulls?per_page=100&state=open").
        and_return(body: prs_body, headers: json_header)
    end

    context "fewer than open_pull_requests_limit" do
      let(:open_pull_requests_limit) { 5 }

      it "creates a new pull request" do
        expect(pr_service).to receive(:publish_changes)
        job.perform_now
      end
    end

    context "and the pending pull request falls outside of the open_pull_requests_limit" do
      let(:open_pull_requests_limit) { 4 }

      let(:first_pending_pr) do
        pr = PendingPullRequest.create!(
          update_job: update_job,
          updated_dependency_details: updated_dependency_details,
          sort_key: 1,
        )
        pr.encrypted_dependency_files_blob.attach(
          io: StringIO.new(encrypt_temporary_file_blob(files.to_json)),
          filename: pr.id,
          content_type: "application/octet-stream",
          identify: false,
        )
        pr.message_data = message_data
        pr
      end

      let(:second_pending_pr) do
        pr = PendingPullRequest.create!(
          update_job: update_job,
          updated_dependency_details: updated_dependency_details,
          sort_key: 2,
        )
        pr.encrypted_dependency_files_blob.attach(
          io: StringIO.new(encrypt_temporary_file_blob(files.to_json)),
          filename: pr.id,
          content_type: "application/octet-stream",
          identify: false,
        )
        pr.message_data = message_data
        pr
      end

      before do
        first_pending_pr
        first_pending_pr.id = pending_pr.id - 1
        second_pending_pr
        second_pending_pr.id = pending_pr.id - 2
      end

      it "retries the job" do
        expect { job.perform_now }.to have_enqueued_job(described_class)
      end
    end

    context "equal to open_pull_requests_limit" do
      let(:open_pull_requests_limit) { 3 }

      it "does not create a new pull request" do
        expect(pr_service).not_to receive(:publish_changes)
        job.perform_now
      end

      it "abandons the pending pull request" do
        expect { job.perform_now }.
          to change { pending_pr.reload.current_state }.from("pending").to("abandoned")
      end

      it "creates update job error" do
        expect { job.perform_now }.
          to change { update_job.update_job_errors.count }.
          from(0).to(1)
        expect(update_job.update_job_errors.first.error_type).
          to eq("open_pull_request_limit_exceeded")
      end

      it "halts with a HaltJobError rather than a failure error" do
        allow(Dependabot::Logger).to receive(:log_exception)
        job.perform_now
        expect(Dependabot::Logger).to have_received(:log_exception).with(
          an_instance_of(described_class::HaltJobError),
          msg: "PR error handled, stopping job."
        )
      end
    end

    context "greater than open_pull_requests_limit" do
      let(:open_pull_requests_limit) { 2 }

      it "does not create a new pull request" do
        expect(pr_service).not_to receive(:publish_changes)
        job.perform_now
      end

      it "abandons the pending pull request" do
        expect { job.perform_now }.
          to change { pending_pr.reload.current_state }.from("pending").to("abandoned")
      end

      it "creates update job error" do
        expect { job.perform_now }.
          to change { update_job.update_job_errors.count }.
          from(0).to(1)
        expect(update_job.update_job_errors.first.error_type).
          to eq("open_pull_request_limit_exceeded")
      end

      context "when there are a large number of open PRs" do
        let(:links_header) do
          {
            "Content-Type" => "application/json",
            "Link" => "<#{repo_url}pulls?state=open&page=2>; rel=\"next\", " \
                      "<#{repo_url}pulls?state=open&page=199>; rel=\"last\"",
          }
        end

        before do
          stub_request(:get, repo_url + "pulls?per_page=100&state=open").
            and_return(body: "[]", headers: links_header)

          [21, 22, 23].each do |github_number|
            pr_body = fixture("github_responses/pull_request_mergeable.json").
                      gsub("18", github_number.to_s)
            pr_url = github_url + "repos/" + repo.full_name +
                     "/pulls/#{github_number}"
            stub_request(:get, pr_url).
              and_return(body: pr_body, headers: json_header)
          end
        end

        it "does not create a new pull request" do
          expect(pr_service).not_to receive(:publish_changes)
          job.perform_now
        end
      end
    end
  end

  context "when there is a previous, edited PR for the same dependency" do
    let(:previous_update_job) { create(:update_job, update_config: update_config) }
    let(:previous_pull_request) do
      create(
        :pull_request,
        repo: repo,
        update_job: previous_update_job,
        dependencies: [updated_dependency_hash.merge("version" => old_version)],
        github_number: 21,
        dependabot_commit_sha: "edited",
      )
    end
    let(:has_user_commits) { true }
    let(:state) { "open" }

    before do
      # Includes a single PR (#21)
      stub_request(:get, repo_url + "issues/21/comments").
        and_return(body: fixture("github_responses/issue_comments.json"), headers: json_header)
      stub_request(:post, repo_url + "issues/21/comments").
        and_return(body: fixture("github_responses/issue_comment.json"), headers: json_header)
      allow(pr_service).to receive_messages(
        get_pull_requests: [
          MonolithTwirp::Dependabot::PullRequests::V1::PullRequest.new(
            repository_id: previous_pull_request.repo.github_id,
            github_number: previous_pull_request.github_number,
            state: state,
            has_user_commits: has_user_commits,
          ),
        ],
      )
    end

    it "does not create a new pull request, and comments on the old one" do
      expect { job.perform_now }.not_to have_enqueued_job(CreatePullRequestOnDependabot)
      expect(pr_service).not_to have_received(:check_pull_request_eligibility)
      expect(WebMock).to have_requested(:post, repo_url + "issues/21/comments")
    end

    it "creates an update job error and presents the error" do
      expect { job.perform_now }.
        to change { update_job.update_job_errors.count }.
        from(0).to(1)

      update_job_error = update_job.update_job_errors.last
      expect(update_job_error.error_type).to eq("edited_pull_request_exists")
      expect(update_job_error.error_details).to eq(
        {
          "edited-pull-request-id" => previous_pull_request.id,
          "updated-dependencies" => [{ "dependency-name" => "business" }],
        }
      )
      presenter = UpdateJobErrorPresenter.new(update_job: update_job, error_hash: update_job_error.error_hash)
      expect(presenter.issue_title).to include("pull request for business")
      expect(presenter.issue_body).to include("pull request for `business`")
    end

    it "halts with a HaltJobError rather than a failure error" do
      allow(Dependabot::Logger).to receive(:log_exception)
      job.perform_now
      expect(Dependabot::Logger).to have_received(:log_exception).with(
        an_instance_of(described_class::HaltJobError),
        msg: "PR error handled, stopping job."
      )
    end

    context "for the same version" do
      let(:old_version) { "1.8.0" }

      it "does not create a new pull request or comment on the old one" do
        expect { job.perform_now }.not_to have_enqueued_job(CreatePullRequestOnDependabot)
        expect(pr_service).not_to have_received(:check_pull_request_eligibility)
        expect(WebMock).not_to have_requested(:post, repo_url + "issues/21/comments")
      end
    end

    context "that has been commented on previously" do
      before do
        stub_request(:get, repo_url + "issues/21/comments").
          and_return(body: fixture("github_responses/issue_comments_with_new_version.json"), headers: json_header)
      end

      it "does not create a new pull request or comment on the old one" do
        expect { job.perform_now }.not_to have_enqueued_job(CreatePullRequestOnDependabot)
        expect(pr_service).not_to have_received(:check_pull_request_eligibility)
        expect(WebMock).
          not_to have_requested(:post, repo_url + "issues/21/comments")
      end
    end

    context "that is closed" do
      let(:state) { "closed" }

      it "creates a new pull request" do
        expect { job.perform_now }.to have_enqueued_job(CreatePullRequestOnDependabot)
        expect(pr_service).to have_received(:create_pull_request)
      end
    end

    context "that has not been edited" do
      let(:has_user_commits) { false }

      it "creates a new pull request" do
        expect { job.perform_now }.to have_enqueued_job(CreatePullRequestOnDependabot)
        expect(pr_service).to have_received(:create_pull_request)
      end
    end

    context "when the pending pull request is a grouped update" do
      let(:dependency_group) { create(:dependency_group, name: "my-deps") }

      before do
        pending_pr.update!(dependency_group: dependency_group, grouped_update: true)
      end

      it "creates a new pull request" do
        expect { job.perform_now }.to have_enqueued_job(CreatePullRequestOnDependabot)
        expect(pr_service).to have_received(:create_pull_request)
      end
    end
  end

  context "when running with deleted pending pull request" do
    before do
      pending_pr.delete
    end

    it "does not enqueue or attempt to retry the job" do
      perform_enqueued_jobs do
        expect { perform_later }.not_to have_enqueued_job(described_class)
      end
    end

    it "does not raise an error" do
      perform_enqueued_jobs do
        expect { perform_later }.not_to raise_error
      end
    end

    it "logs the exception" do
      expect(Dependabot::Logger).to receive(:log_exception) do |exception, data|
        expect(exception).to be_a(ActiveJob::DeserializationError)
        expect(exception.cause).to be_a(ActiveRecord::RecordNotFound)
        expect(data).to eq({ "code.namespace": "CreatePullRequestOnGitHub" })
      end

      perform_enqueued_jobs { perform_later }
    end

    it "emits a metric" do
      expect(MetricsClient).to receive(:increment).
        with("create_pull_request.pending_pull_request_gone")

      perform_enqueued_jobs { perform_later }
    end
  end

  context "when checking if a branch and PR can be created on GitHub" do
    before do
      allow(pr_service).to receive(:check_pull_request_eligibility).
        with(
          repo:,
          dependabot_branch_name: anything,
          base_commit_sha: update_job.base_commit_sha,
          base_branch_name: update_job.target_branch,
          require_up_to_date_base: false,
        ).
        and_return(result)
    end

    context "returns RESULT_BASE_NOT_UP_TO_DATE" do
      let(:result) do
        described_class::EligibilityResult::RESULT_BASE_NOT_UP_TO_DATE
      end

      it "does not raise an error" do
        expect { job.perform_now }.not_to raise_error
      end

      it "logs an update job error" do
        expect { job.perform_now }.to change { update_job.update_job_errors.count }.from(0).to(1)
        expect(update_job.update_job_errors.last.error_type).to eql("pull_request_creation_failure")
        expect(update_job.update_job_errors.last.error_details).to match(
          "message" => "This job's base commit is not up to date"
        )
      end
    end

    context "returns RESULT_EXISTING_BRANCH_HAS_MULTIPLE_COMMITS" do
      let(:result) do
        described_class::EligibilityResult::RESULT_EXISTING_BRANCH_HAS_MULTIPLE_COMMITS
      end

      it "does not raise an error" do
        expect { job.perform_now }.not_to raise_error
      end

      it "logs an update job error" do
        expect { job.perform_now }.to change { update_job.update_job_errors.count }.from(0).to(1)
        expect(update_job.update_job_errors.last.error_type).to eql("pull_request_creation_failure")
        expect(update_job.update_job_errors.last.error_details).to match(
          "message" => "Branch contains incompatible changes"
        )
      end
    end

    context "returns RESULT_UNMERGED_PR_EXISTS" do
      let(:result) do
        described_class::EligibilityResult::RESULT_UNMERGED_PR_EXISTS
      end

      it "does not raise an error" do
        expect { job.perform_now }.not_to raise_error
      end

      it "logs an update job error" do
        expect { job.perform_now }.to change { update_job.update_job_errors.count }.from(0).to(1)
        expect(update_job.update_job_errors.last.error_type).to eql("pull_request_creation_failure")
        expect(update_job.update_job_errors.last.error_details).to match(
          "message" => "PR for branch already exists"
        )
      end
    end

    context "returns RESULT_USER_EDITED_BRANCH_EXISTS" do
      let(:result) do
        described_class::EligibilityResult::RESULT_USER_EDITED_BRANCH_EXISTS
      end

      it "does not raise an error" do
        expect { job.perform_now }.not_to raise_error
      end

      it "logs an update job error" do
        expect { job.perform_now }.to change { update_job.update_job_errors.count }.from(0).to(1)
        expect(update_job.update_job_errors.last.error_type).to eql("pull_request_creation_halted")
        expect(update_job.update_job_errors.last.error_details).to match(
          "message" => "Branch contains non-Dependabot commits"
        )
      end
    end
  end

  context "error handling" do
    context "captures telemetry about the error" do
      before do
        allow(update_job).to receive(:increment_metric).and_call_original
      end

      it "logs the error" do
        err = described_class::FailJobError.new("test", reason: :test)
        allow(pr_service).to receive(:publish_changes).and_raise(err)

        expect(Dependabot::Logger).to receive(:log_exception).with(err, msg: "PR error handled, stopping job.")
        job.perform_now
      end

      it "increments error metrics with an error reason" do
        err = described_class::FailJobError.new("test", reason: :test)
        allow(pr_service).to receive(:publish_changes).and_raise(err)

        job.perform_now
        expect(update_job).to have_received(:increment_metric).
          with("create_pull_request.error_handled",
               tags: { error: :test, grouped_update: false, v2: true, expected: false })
      end

      it "increments error metrics without an error reason" do
        err = described_class::FailJobError.new("test", reason: :test)
        allow(pr_service).to receive(:publish_changes).and_raise(err)

        job.perform_now
        expect(update_job).to have_received(:increment_metric).
          with("create_pull_request.error_handled",
               tags: { grouped_update: false, v2: true, error: :test, expected: false })
      end

      it "increments error metrics for errors that don't contain a reason" do
        err = StandardError.new("test")
        allow(pr_service).to receive(:publish_changes).and_raise(err)

        expect { job.perform_now }.to raise_error(err)
        expect(update_job).to have_received(:increment_metric).
          with("create_pull_request.error_handled",
               tags: { error: "standard_error", grouped_update: false, v2: true, expected: false })
      end

      it "increments error metrics for errors that require synchronization" do
        err = described_class::SynchronizeRepoStateError.new("test", reason: "Repo archived")
        allow(pr_service).to receive(:publish_changes).and_raise(err)

        job.perform_now

        expect(update_job).to have_received(:increment_metric).
          with("create_pull_request.error_handled",
               tags: { error: "Repo archived", grouped_update: false, v2: true, expected: false }).
          once
      end

      it "logs retryable errors" do
        allow(pr_service).to receive(:publish_changes).
          and_raise(described_class::RetryJobError.new("test"))
        expect { job.perform_now }.to have_enqueued_job(described_class)

        expect(update_job).to have_received(:increment_metric).
          with("create_pull_request.retry", {
                 tags: {
                   grouped_update: false,
                   v2: true,
                   queue: "create_pull_request_p2",
                   retryable_error: "PrioritizedJobs::CreatePullRequestOnGitHub::Default::RetryJobError",
                   attempts: 1,
                 },
               }).once
      end

      it "classifies expected errors as such" do
        err = described_class::HaltJobError.new("test", reason: "open_pull_request_limit_exceeded")
        allow(pr_service).to receive(:publish_changes).and_raise(err)

        job.perform_now

        expect(update_job).to have_received(:increment_metric).
          with("create_pull_request.error_handled",
               tags: { error: "open_pull_request_limit_exceeded", grouped_update: false, v2: true, expected: true })
      end

      it "classifies unexpected errors as such" do
        err = StandardError.new("huh?")
        allow(pr_service).to receive(:publish_changes).and_raise(err)

        expect { job.perform_now }.to raise_error(err)
        expect(update_job).to have_received(:increment_metric).
          with("create_pull_request.error_handled",
               tags: { error: "standard_error", grouped_update: false, v2: true, expected: false })
      end
    end

    it "retries retryable errors" do
      allow(pr_service).to receive(:publish_changes).
        and_raise(described_class::RetryJobError.new("test"))
      expect { job.perform_now }.to have_enqueued_job(described_class)
    end

    it "changes queue to create_pull_request_p3 on retry" do
      3.times do
        allow(pr_service).to receive(:publish_changes).
          and_raise(described_class::RetryJobError.new("test"))
        expect { job.perform_now }.to have_enqueued_job(described_class).on_queue("create_pull_request_p2")
      end
      expect { job.perform_now }.to have_enqueued_job(described_class).on_queue("create_pull_request_p3")
    end

    context "when retries are exhausted" do
      before do
        allow(pr_service).to receive(:publish_changes).
          and_raise(described_class::RetryJobError.new("test"))
      end

      it "abandons the pull request" do
        perform_enqueued_jobs do
          expect { job.perform_now }.to(
            change { pending_pr.reload.current_state }.from("pending").to("abandoned")
          )
        end
      end

      it "creates an update job error and presents the error" do
        perform_enqueued_jobs do
          expect { job.perform_now }.to(
            change { update_job.update_job_errors.count }.from(0).to(1)
          )

          expect(update_job.update_job_errors.last.error_type).to eql("pull_request_creation_failure")
        end
      end
    end

    it "handles non-retryable failure errors" do
      allow(pr_service).to receive(:publish_changes).
        and_raise(described_class::FailJobError.new("test", reason: :test))
      expect { job.perform_now }.to change { update_job.update_job_errors.count }.from(0).to(1)

      update_job_error = update_job.update_job_errors.last
      expect(update_job_error.error_type).to eq("pull_request_creation_failure")
      expect(update_job_error.error_details).to be_nil
    end

    it "handles non-retryable halting errors" do
      allow(pr_service).to receive(:publish_changes).
        and_raise(described_class::HaltJobError.new("test", reason: :test))
      expect { job.perform_now }.to change { update_job.update_job_errors.count }.from(0).to(1)

      update_job_error = update_job.update_job_errors.last
      expect(update_job_error.error_type).to eq("pull_request_creation_halted")
      expect(update_job_error.error_details).to be_nil
    end

    it "handles unexpected errors" do
      err = StandardError.new("test")
      allow(pr_service).to receive(:publish_changes).and_raise(err)
      expect { job.perform_now }.
        to raise_error(err).
        and(change { update_job.update_job_errors.count }.from(0).to(1))

      update_job_error = update_job.update_job_errors.last
      expect(update_job_error.error_type).to eq("pull_request_creation_failure")
      expect(update_job_error.error_details).to be_nil
    end

    it "handles SynchronizeRepoState::HANDLED_ERRORS" do
      repo_synchronizer_result = SynchronizeRepoState::SynchronizeRepoStateResult.success
      repo_synchronizer = instance_double(SynchronizeRepoState, run: repo_synchronizer_result)

      allow(SynchronizeRepoState).
        to receive(:new).with(repo: repo, event_source: anything).
        and_return(repo_synchronizer)

      allow(pr_service).to receive(:publish_changes).and_raise(Octokit::NotFound)

      expect { job.perform_now }.to have_enqueued_job(described_class)
    end

    context "when handling RemediateNoInstallationError" do
      let(:err) { described_class::RemediateNoInstallationError.new("test", reason: :installation_not_found) }

      before do
        allow(pr_service).to receive(:publish_changes).and_raise(err)
      end

      context "when the job is scheduled" do
        let(:update_job) do
          create(:update_job, update_config: update_config, github_request_id: nil, base_commit_sha: sha,
                              trigger_type: "schedule")
        end

        it "abandons the pending pull request" do
          expect { job.perform_now }.to change { pending_pr.reload.current_state }.from("pending").to("abandoned")
        end

        it "deactivates the repo" do
          deactivate_repo = instance_double(DeactivateRepo, run: nil)
          allow(DeactivateRepo).to receive(:new).with(repo_github_id: repo.github_id,
                                                      account: account).and_return(deactivate_repo)

          job.perform_now

          expect(DeactivateRepo).to have_received(:new).with(repo_github_id: repo.github_id, account: account)
          expect(deactivate_repo).to have_received(:run)
        end

        it "does not enqueue a retry" do
          allow(DeactivateRepo).to receive(:new).and_return(instance_double(DeactivateRepo, run: nil))

          expect { job.perform_now }.not_to have_enqueued_job(described_class)
        end
      end

      context "when the job is a security update" do
        let(:update_job) do
          create(:update_job, update_config: update_config, github_request_id: "123", base_commit_sha: sha,
                              trigger_type: "scan")
        end

        it "retries the job" do
          expect { job.perform_now }.to have_enqueued_job(described_class)
        end

        it "does not abandon the pending pull request" do
          expect { job.perform_now }.not_to change { pending_pr.reload.current_state }
        end

        it "does not deactivate the repo" do
          expect(DeactivateRepo).not_to receive(:new)

          job.perform_now
        end
      end
    end

    it "sets update job metadata if the error is presentable" do
      presentable_reason = described_class::ErrorHandling::PRESENTABLE_ERRORS.find { |e| e.is_a?(Symbol) }
      allow(pr_service).to receive(:publish_changes).
        and_raise(described_class::FailJobError.new("presentable message", reason: presentable_reason))
      expect { job.perform_now }.to change { update_job.update_job_errors.count }.from(0).to(1)

      update_job_error = update_job.update_job_errors.last
      expect(update_job_error.error_type).to eq("pull_request_creation_failure")
      expect(update_job_error.error_details).to eq({ "message" => "presentable message" })
    end

    context "when rescuing a TwirpError" do
      let(:error) { Twirp::Error.internal("error") }

      context "when fetching existing pull requests" do
        before do
          create_previous_pull_request
          allow(pr_service).to receive(:get_pull_requests).
            and_raise(GitHub::Twirp::DependabotPullRequests::TwirpError.for_error("test", error))
        end

        it "creates an update job error" do
          perform_enqueued_jobs do
            expect do
              job.perform_now
            end.to change { update_job.update_job_errors.count }.from(0).to(1)

            expect(update_job.update_job_errors.last.error_type).to eql("pull_request_creation_failure")
            expect(update_job.update_job_errors.last.error_details).to eq({ "http_status_code" => 500 })
          end
        end

        context "when the error is retryable" do
          let(:error) { Twirp::Error.internal("error") }

          it "retries the job" do
            expect { job.perform_now }.to have_enqueued_job(described_class)
          end
        end

        context "when the error is not retryable" do
          let(:error) { Twirp::Error.not_found("error") }

          it "does not retry the job" do
            expect { job.perform_now }.not_to have_enqueued_job(described_class)
          end
        end
      end

      context "when checking pull request eligibility" do
        before do
          allow(pr_service).to receive(:check_pull_request_eligibility).
            and_raise(GitHub::Twirp::DependabotPullRequests::TwirpError.for_error("test", error))
        end

        it "creates an update job error" do
          perform_enqueued_jobs do
            expect do
              job.perform_now
            end.to change { update_job.update_job_errors.count }.from(0).to(1)

            expect(update_job.update_job_errors.last.error_type).to eql("pull_request_creation_failure")
            expect(update_job.update_job_errors.last.error_details).to eq({ "http_status_code" => 500 })
          end
        end

        context "when the error is retryable" do
          let(:error) { Twirp::Error.internal("error") }

          it "retries the job" do
            expect { job.perform_now }.to have_enqueued_job(described_class)
          end
        end

        context "when the error is not retryable" do
          let(:error) { Twirp::Error.not_found("error") }

          it "does not retry the job" do
            expect { job.perform_now }.not_to have_enqueued_job(described_class)
          end
        end
      end

      context "when publishing changes" do
        before do
          allow(pr_service).to receive(:publish_changes).
            and_raise(GitHub::Twirp::DependabotPullRequests::TwirpError.for_error("test", error))
        end

        it "creates an update job error" do
          perform_enqueued_jobs do
            expect do
              job.perform_now
            end.to change { update_job.update_job_errors.count }.from(0).to(1)

            expect(update_job.update_job_errors.last.error_type).to eql("pull_request_creation_failure")
            expect(update_job.update_job_errors.last.error_details).to eq({ "http_status_code" => 500 })
          end
        end

        context "when the error is retryable" do
          let(:error) { Twirp::Error.internal("error") }

          it "retries the job" do
            expect { job.perform_now }.to have_enqueued_job(described_class)
          end
        end

        context "when the error is not retryable" do
          let(:error) { Twirp::Error.not_found("error") }

          it "does not retry the job" do
            expect { job.perform_now }.not_to have_enqueued_job(described_class)
          end
        end
      end

      context "when creating a pull request" do
        before do
          allow(pr_service).to receive(:create_pull_request).
            and_raise(GitHub::Twirp::DependabotPullRequests::TwirpError.for_error("test", error))
        end

        it "creates an update job error" do
          perform_enqueued_jobs do
            expect do
              job.perform_now
            end.to change { update_job.update_job_errors.count }.from(0).to(1)

            expect(update_job.update_job_errors.last.error_type).to eql("pull_request_creation_failure")
            expect(update_job.update_job_errors.last.error_details).to eq({ "http_status_code" => 500 })
          end
        end

        context "when the error is retryable" do
          let(:error) { Twirp::Error.internal("error") }

          it "retries the job" do
            expect { job.perform_now }.to have_enqueued_job(described_class)
          end
        end

        context "when the error is not retryable" do
          let(:error) { Twirp::Error.not_found("error") }

          it "does not retry the job" do
            expect { job.perform_now }.not_to have_enqueued_job(described_class)
          end
        end
      end
    end

    context "when rescuing an API ServiceError" do
      let(:error_type) { MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_RATE_LIMITED }

      context "when fetching existing pull requests" do
        before do
          create_previous_pull_request

          allow(pr_service).to receive(:get_pull_requests).
            and_raise(GitHub::Twirp::DependabotPullRequests::ServiceError.for_error(
                        "error",
                        MonolithTwirp::Dependabot::PullRequests::V1::Error.new(
                          type: error_type,
                          message: "details"
                        )
                      ))
        end

        it "creates an update job error" do
          perform_enqueued_jobs do
            expect do
              job.perform_now
            end.to change { update_job.update_job_errors.count }.from(0).to(1)

            expect(update_job.update_job_errors.last.error_type).to eql("pull_request_creation_failure")
            expect(update_job.update_job_errors.last.error_details).to be_nil
          end
        end

        context "when the error is presentable" do
          let(:error_type) { MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_GIT }

          it "creates an update job error with details" do
            perform_enqueued_jobs do
              expect do
                job.perform_now
              end.to change { update_job.update_job_errors.count }.from(0).to(1)

              expect(update_job.update_job_errors.last.error_type).to eql("pull_request_creation_failure")
              expect(update_job.update_job_errors.last.error_details).
                to eq({ "message" => "error: details" })
            end
          end
        end

        context "when the error is retryable" do
          let(:error_type) { MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_UNEXPECTED_ERROR }

          it "retries the job" do
            expect { job.perform_now }.to have_enqueued_job(described_class)
          end
        end

        context "when the error is not retryable" do
          let(:error_type) { MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_REQUEST_TOO_LARGE }

          it "does not retry the job" do
            expect { job.perform_now }.not_to have_enqueued_job(described_class)
          end
        end

        context "when the error should cause a repo state sync" do
          let(:error_type) { MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_REPO_ARCHIVED }

          it "retries the job when synchronizing repo state returns success" do
            repo_synchronizer_result = SynchronizeRepoState::SynchronizeRepoStateResult.success
            repo_synchronizer = instance_double(SynchronizeRepoState, run: repo_synchronizer_result)

            allow(SynchronizeRepoState).
              to receive(:new).with(repo: repo, event_source: anything).
              and_return(repo_synchronizer)

            expect { job.perform_now }.to have_enqueued_job(described_class)
            expect(repo_synchronizer).to have_received(:run)
          end

          it "does not retry the job when synchronizing repo state returns an error" do
            expect { job.perform_now }.not_to have_enqueued_job(described_class)
          end
        end

        context "when the error is ERROR_TYPE_DEPENDABOT_NOT_INSTALLED" do
          let(:error_type) { MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_DEPENDABOT_NOT_INSTALLED }

          context "when job is scheduled" do
            before do
              update_job.update!(trigger_type: "schedule")
            end

            it "abandons the pending pull request" do
              allow(DeactivateRepo).to receive(:new).and_return(instance_double(DeactivateRepo, run: nil))
              expect { job.perform_now }.to change { pending_pr.reload.current_state }.from("pending").to("abandoned")
            end

            it "deactivates the repo" do
              deactivate_repo = instance_double(DeactivateRepo, run: nil)
              allow(DeactivateRepo).to receive(:new).with(repo_github_id: repo.github_id,
                                                          account: account).and_return(deactivate_repo)
              job.perform_now
              expect(DeactivateRepo).to have_received(:new).with(repo_github_id: repo.github_id, account: account)
              expect(deactivate_repo).to have_received(:run)
            end
          end

          context "when job is a security update" do
            before do
              update_job.update!(trigger_type: "scan", github_request_id: "123")
            end

            it "retries the job" do
              expect { job.perform_now }.to have_enqueued_job(described_class)
            end
          end
        end
      end

      context "when checking pull request eligibility" do
        before do
          allow(pr_service).to receive(:check_pull_request_eligibility).
            and_raise(GitHub::Twirp::DependabotPullRequests::ServiceError.for_error(
                        "error",
                        MonolithTwirp::Dependabot::PullRequests::V1::Error.new(
                          type: error_type,
                          message: "details"
                        )
                      ))
        end

        it "creates an update job error" do
          perform_enqueued_jobs do
            expect do
              job.perform_now
            end.to change { update_job.update_job_errors.count }.from(0).to(1)

            expect(update_job.update_job_errors.last.error_type).to eql("pull_request_creation_failure")
            expect(update_job.update_job_errors.last.error_details).to be_nil
          end
        end

        context "when the error is presentable" do
          let(:error_type) { MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_GIT }

          it "creates an update job error with details" do
            perform_enqueued_jobs do
              expect do
                job.perform_now
              end.to change { update_job.update_job_errors.count }.from(0).to(1)

              expect(update_job.update_job_errors.last.error_type).to eql("pull_request_creation_failure")
              expect(update_job.update_job_errors.last.error_details).
                to eq({ "message" => "error: details" })
            end
          end
        end

        context "when the error is retryable" do
          let(:error_type) { MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_UNEXPECTED_ERROR }

          it "retries the job" do
            expect { job.perform_now }.to have_enqueued_job(described_class)
          end
        end

        context "when the error is not retryable" do
          let(:error_type) { MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_REQUEST_TOO_LARGE }

          it "does not retry the job" do
            expect { job.perform_now }.not_to have_enqueued_job(described_class)
          end
        end

        context "when the error should cause a repo state sync" do
          let(:error_type) { MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_REPO_ARCHIVED }

          it "retries the job when synchronizing repo state returns success" do
            repo_synchronizer_result = SynchronizeRepoState::SynchronizeRepoStateResult.success
            repo_synchronizer = instance_double(SynchronizeRepoState, run: repo_synchronizer_result)

            allow(SynchronizeRepoState).
              to receive(:new).with(repo: repo, event_source: anything).
              and_return(repo_synchronizer)

            expect { job.perform_now }.to have_enqueued_job(described_class)
            expect(repo_synchronizer).to have_received(:run)
          end

          it "does not retry the job when synchronizing repo state returns an error" do
            expect { job.perform_now }.not_to have_enqueued_job(described_class)
          end
        end
      end

      context "when publishing changes" do
        before do
          allow(pr_service).to receive(:publish_changes).
            and_raise(GitHub::Twirp::DependabotPullRequests::ServiceError.for_error(
                        "error",
                        MonolithTwirp::Dependabot::PullRequests::V1::Error.new(
                          type: error_type,
                          message: "details"
                        )
                      ))
        end

        it "creates an update job error" do
          perform_enqueued_jobs do
            expect do
              job.perform_now
            end.to change { update_job.update_job_errors.count }.from(0).to(1)

            expect(update_job.update_job_errors.last.error_type).to eql("pull_request_creation_failure")
            expect(update_job.update_job_errors.last.error_details).to be_nil
          end
        end

        context "when the error is presentable" do
          let(:error_type) { MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_GIT }

          it "creates an update job error with details" do
            perform_enqueued_jobs do
              expect do
                job.perform_now
              end.to change { update_job.update_job_errors.count }.from(0).to(1)

              expect(update_job.update_job_errors.last.error_type).to eql("pull_request_creation_failure")
              expect(update_job.update_job_errors.last.error_details).
                to eq({ "message" => "error: details" })
            end
          end
        end

        context "when the error is retryable" do
          let(:error_type) { MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_UNEXPECTED_ERROR }

          it "retries the job" do
            expect { job.perform_now }.to have_enqueued_job(described_class)
          end
        end

        context "when the error is not retryable" do
          let(:error_type) { MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_REQUEST_TOO_LARGE }

          it "does not retry the job" do
            expect { job.perform_now }.not_to have_enqueued_job(described_class)
          end
        end

        context "when the error should cause a repo state sync" do
          let(:error_type) { MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_REPO_ARCHIVED }

          it "retries the job when synchronizing repo state returns success" do
            repo_synchronizer_result = SynchronizeRepoState::SynchronizeRepoStateResult.success
            repo_synchronizer = instance_double(SynchronizeRepoState, run: repo_synchronizer_result)

            allow(SynchronizeRepoState).
              to receive(:new).with(repo: repo, event_source: anything).
              and_return(repo_synchronizer)

            expect { job.perform_now }.to have_enqueued_job(described_class)
            expect(repo_synchronizer).to have_received(:run)
          end

          it "does not retry the job when synchronizing repo state returns an error" do
            expect { job.perform_now }.not_to have_enqueued_job(described_class)
          end
        end
      end

      context "when creating a pull request" do
        before do
          allow(pr_service).to receive(:create_pull_request).
            and_raise(GitHub::Twirp::DependabotPullRequests::ServiceError.for_error(
                        "error",
                        MonolithTwirp::Dependabot::PullRequests::V1::Error.new(
                          type: error_type,
                          message: "details"
                        )
                      ))
        end

        it "creates an update job error" do
          perform_enqueued_jobs do
            expect do
              job.perform_now
            end.to change { update_job.update_job_errors.count }.from(0).to(1)

            expect(update_job.update_job_errors.last.error_type).to eql("pull_request_creation_failure")
            expect(update_job.update_job_errors.last.error_details).to be_nil
          end
        end

        context "when the error is presentable" do
          let(:error_type) { MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_GIT }

          it "creates an update job error with details" do
            perform_enqueued_jobs do
              expect do
                job.perform_now
              end.to change { update_job.update_job_errors.count }.from(0).to(1)

              expect(update_job.update_job_errors.last.error_type).to eql("pull_request_creation_failure")
              expect(update_job.update_job_errors.last.error_details).
                to eq({ "message" => "error: details" })
            end
          end
        end

        context "when the error is retryable" do
          let(:error_type) { MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_UNEXPECTED_ERROR }

          it "retries the job" do
            expect { job.perform_now }.to have_enqueued_job(described_class)
          end
        end

        context "when the error is not retryable" do
          let(:error_type) { MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_REQUEST_TOO_LARGE }

          it "does not retry the job" do
            expect { job.perform_now }.not_to have_enqueued_job(described_class)
          end
        end

        context "when the error should cause a repo state sync" do
          let(:error_type) { MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_REPO_ARCHIVED }

          it "retries the job when synchronizing repo state returns success" do
            repo_synchronizer_result = SynchronizeRepoState::SynchronizeRepoStateResult.success
            repo_synchronizer = instance_double(SynchronizeRepoState, run: repo_synchronizer_result)

            allow(SynchronizeRepoState).
              to receive(:new).with(repo: repo, event_source: anything).
              and_return(repo_synchronizer)

            expect { job.perform_now }.to have_enqueued_job(described_class)
            expect(repo_synchronizer).to have_received(:run)
          end

          it "does not retry the job when synchronizing repo state returns an error" do
            expect { job.perform_now }.not_to have_enqueued_job(described_class)
          end
        end
      end
    end
  end

  context "forward flow to update_job when there is an existing PR" do
    let(:pull_request) do
      previous_update_job = create(:update_job, update_config: update_config)
      create(
        :pull_request,
        repo: repo,
        update_job: previous_update_job,
        dependencies: [updated_dependency_hash.merge("version" => old_version)],
        github_number: 21,
        head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
        dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
      )
    end
    let(:pull_request_transition) do
      pull_request.transition_to!(:updating)
      pull_request.pull_request_transitions.last
    end

    before do
      update_job.update!(pull_request_transition: pull_request_transition)
    end

    it "enqueues an update job" do
      expect { job.perform_now }.to have_enqueued_job(UpdatePullRequestJob)
      expect(pr_service).not_to have_received(:create_pull_request)
    end

    it "forwards message data to the pending pull request update" do
      job.perform_now

      pending_update = PendingPullRequestUpdate.last
      expect(pending_update.message_data).to include(
        "pr_title" => "some pr title",
        "pr_body" => "some pr body",
        "commit_message" => "some commit message"
      )
    end
  end

  context "when pr_being_updated value exists but the names do not match" do
    it "does not enqueue an update job" do
      updated_dependency_details.first["name"] = "updated_name"
      expect { job.perform_now }.not_to have_enqueued_job(UpdatePullRequestJob)
      expect(pr_service).to have_received(:create_pull_request)
    end
  end
end
