# frozen_string_literal: true

require "rails_helper"
require "github_helpers"

RSpec.describe GitHub::Twirp::DependabotPullRequests do
  let(:github_api_url) do
    "http://host.docker.internal:3000/api/v3/"
  end

  let(:base_client) do
    MonolithTwirp::Dependabot::PullRequests::V1::PullRequestAPIClient.new(
      GitHub::Twirp::Client.new(
        github_api_url: github_api_url.to_s,
        hmac_key: "dependabotapihmac"
      ).connection
    )
  end

  let(:client) { described_class.new(client: base_client, tenant: tenant) }
  let(:tenant) { repo.account.tenant }
  let(:repo) { create(:repo) }

  describe "#get_pull_requests" do
    let(:response_error) { nil }
    let(:twirp_error) { nil }
    let(:pull_requests) do
      [
        MonolithTwirp::Dependabot::PullRequests::V1::PullRequest.new(
          base_ref: "main",
          base_sha: "1234567",
          github_number: 1,
          has_user_commits: false,
          repository_id: 1,
          state: "open"
        ),
      ]
    end

    before do
      allow(base_client).to receive(:get_pull_requests).
        and_return(Twirp::ClientResp.new(
                     data: MonolithTwirp::Dependabot::PullRequests::V1::GetPullRequestsResponse.new(
                       pull_requests: pull_requests,
                       error: response_error,
                     ),
                     error: twirp_error,
                   ))
    end

    it "loads pull request information from GitHub" do
      result = client.get_pull_requests(repo:, github_pr_numbers: [1, 2, 3])

      expect(result).to eq(pull_requests)
      expect(MetricsClient).to have_received(:distribution).with(
        "twirp.github.dependabot_pull_requests.get_pull_requests",
        anything,
        tags: { response_code: :ok }
      )
      expect(base_client).to have_received(:get_pull_requests).
        with(MonolithTwirp::Dependabot::PullRequests::V1::GetPullRequestsRequest.new(
               repository_id: repo.github_id, github_pr_numbers: [1, 2, 3],
               state: "open", include_skipped_commits: false,
             ), anything)
    end

    context "in Proxima", :proxima do
      it "sets tenancy headers on the request" do
        client.get_pull_requests(repo:, github_pr_numbers: [1, 2, 3])
        expect(base_client).to have_received(:get_pull_requests).
          with(anything, { headers: { "X-GitHub-Tenant" => tenant.slug } })
      end

      context "when the tenant doesn't have a slug" do
        let(:tenant) { NullTenant.new }

        it "raises an error" do
          expect { client.get_pull_requests(repo:, github_pr_numbers: [1, 2, 3]) }.
            to raise_error(GitHub::Twirp::Error)
        end
      end
    end

    context "not in Proxima", proxima: false do
      it "does not set tenancy headers on the request" do
        client.get_pull_requests(repo:, github_pr_numbers: [1, 2, 3])
        expect(base_client).to have_received(:get_pull_requests).
          with(anything, {})
      end
    end

    context "with a twirp response error" do
      let(:twirp_error) { Twirp::Error.not_found("test") }

      it "raises a TwirpError" do
        expect { client.get_pull_requests(repo:, github_pr_numbers: [1, 2, 3]) }.to raise_error(
          GitHub::Twirp::DependabotPullRequests::TwirpError
        )

        expect(MetricsClient).to have_received(:distribution).with(
          "twirp.github.dependabot_pull_requests.get_pull_requests",
          anything,
          tags: { response_code: twirp_error.code }
        )
      end
    end

    context "with an error in the API response data" do
      let(:response_error) do
        MonolithTwirp::Dependabot::PullRequests::V1::Error.new(
          type: MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_GIT,
          message: "test",
        )
      end

      it "raises a ServiceError" do
        expect { client.get_pull_requests(repo:, github_pr_numbers: [1, 2, 3]) }.to raise_error(
          GitHub::Twirp::DependabotPullRequests::ServiceError
        )

        expect(MetricsClient).to have_received(:distribution).with(
          "twirp.github.dependabot_pull_requests.get_pull_requests",
          anything,
          tags: { response_code: :ok }
        )
      end
    end
  end

  describe "#check_pull_request_eligibility" do
    let(:response_error) { nil }
    let(:twirp_error) { nil }
    let(:result) { MonolithTwirp::Dependabot::PullRequests::V1::CheckPullRequestEligibilityResponse::Result::RESULT_OK }

    before do
      allow(base_client).to receive(:check_pull_request_eligibility).
        and_return(Twirp::ClientResp.new(
                     data: MonolithTwirp::Dependabot::PullRequests::V1::CheckPullRequestEligibilityResponse.new(
                       result: result,
                       error: response_error,
                     ),
                     error: twirp_error,
                   ))
    end

    it "returns an eligibility result from dotcom" do
      api_result = client.check_pull_request_eligibility(
        repo:, dependabot_branch_name: "dependabot", base_branch_name: nil,
        base_commit_sha: "1234567", require_up_to_date_base: false
      )

      expect(api_result).to eq(:RESULT_OK)
      expect(MetricsClient).to have_received(:distribution).with(
        "twirp.github.dependabot_pull_requests.check_pull_request_eligibility",
        anything,
        tags: { response_code: :ok }
      )
      expect(base_client).to have_received(:check_pull_request_eligibility).
        with(MonolithTwirp::Dependabot::PullRequests::V1::CheckPullRequestEligibilityRequest.new(
               repository_id: repo.github_id, dependabot_branch_name: "dependabot", base_branch_name: nil,
               base_commit_sha: "1234567", require_up_to_date_base: false
             ), anything)
    end

    context "in Proxima", :proxima do
      it "sets tenancy headers on the request" do
        client.check_pull_request_eligibility(
          repo:, dependabot_branch_name: "dependabot", base_branch_name: nil,
          base_commit_sha: "1234567", require_up_to_date_base: false
        )
        expect(base_client).to have_received(:check_pull_request_eligibility).
          with(anything, { headers: { "X-GitHub-Tenant" => tenant.slug } })
      end

      context "when the tenant doesn't have a slug" do
        let(:tenant) { NullTenant.new }

        it "raises an error" do
          expect do
            client.check_pull_request_eligibility(
              repo:, dependabot_branch_name: "dependabot", base_branch_name: nil,
              base_commit_sha: "1234567", require_up_to_date_base: false
            )
          end.to raise_error(GitHub::Twirp::Error)
        end
      end
    end

    context "not in Proxima", proxima: false do
      it "does not set tenancy headers on the request" do
        client.check_pull_request_eligibility(
          repo:, dependabot_branch_name: "dependabot", base_branch_name: nil,
          base_commit_sha: "1234567", require_up_to_date_base: false
        )
        expect(base_client).to have_received(:check_pull_request_eligibility).
          with(anything, {})
      end
    end

    context "with a twirp response error" do
      let(:twirp_error) { Twirp::Error.not_found("test") }

      it "raises a TwirpError" do
        expect do
          client.check_pull_request_eligibility(
            repo:, dependabot_branch_name: "dependabot", base_branch_name: nil,
            base_commit_sha: "1234567", require_up_to_date_base: false
          )
        end.to raise_error(GitHub::Twirp::DependabotPullRequests::TwirpError)

        expect(MetricsClient).to have_received(:distribution).with(
          "twirp.github.dependabot_pull_requests.check_pull_request_eligibility",
          anything,
          tags: { response_code: twirp_error.code }
        )
      end
    end

    context "with an error in the API response data" do
      let(:response_error) do
        MonolithTwirp::Dependabot::PullRequests::V1::Error.new(
          type: MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_GIT,
          message: "test",
        )
      end

      it "raises a ServiceError" do
        expect do
          client.check_pull_request_eligibility(
            repo:, dependabot_branch_name: "dependabot", base_branch_name: nil,
            base_commit_sha: "1234567", require_up_to_date_base: false
          )
        end.to raise_error(GitHub::Twirp::DependabotPullRequests::ServiceError)

        expect(MetricsClient).to have_received(:distribution).with(
          "twirp.github.dependabot_pull_requests.check_pull_request_eligibility",
          anything,
          tags: { response_code: :ok }
        )
      end
    end
  end

  describe "#publish_changes" do
    let(:response_error) { nil }
    let(:twirp_error) { nil }
    let(:branch_values) do
      {
        repository_id: repo.github_id,
        branch_name: "dependabot/branch",
        commit_sha: "1234567",
      }
    end

    let(:files) do
      [
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: "things1",
          directory: "/test",
          type: "file",
          operation: "update",
          support_file: false,
          content_encoding: "utf-8",
          deleted: false
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: "things2",
          directory: "/test",
          type: "file",
          operation: "update",
          support_file: false,
          content_encoding: "utf-8",
          deleted: false
        ),
      ]
    end

    before do
      allow(base_client).to receive(:publish_changes).
        and_return(Twirp::ClientResp.new(
                     data: MonolithTwirp::Dependabot::PullRequests::V1::PublishChangesResponse.new(
                       **branch_values,
                       error: response_error,
                     ),
                     error: twirp_error,
                   ))
    end

    it "returns information about changes published to dotcom" do # rubocop:disable RSpec/ExampleLength
      response = client.publish_changes(
        repo:, dependabot_branch_name: "dependabot", base_commit_sha: "1234567",
        commit_message: "commit", dependency_files: files,
      )

      expect(response.to_h).to eq(**branch_values, error: nil)
      expect(MetricsClient).to have_received(:distribution).with(
        "twirp.github.dependabot_pull_requests.publish_changes",
        anything,
        tags: { response_code: :ok }
      )
      expect(base_client).to have_received(:publish_changes) do |req, _metadata|
        expect(req.repository_id).to eq(repo.github_id)
        expect(req.dependabot_branch_name).to eq("dependabot")
        expect(req.base_commit_sha).to eq("1234567")
        expect(req.commit_message).to eq("commit")
        expect(req.dependency_files.map(&:name)).to eq(files.map(&:name))
      end
    end

    context "in Proxima", :proxima do
      it "sets tenancy headers on the request" do
        client.publish_changes(
          repo:, dependabot_branch_name: "dependabot", base_commit_sha: "1234567",
          commit_message: "commit", dependency_files: [],
        )
        expect(base_client).to have_received(:publish_changes).
          with(anything, { headers: { "X-GitHub-Tenant" => tenant.slug } })
      end

      context "when the tenant doesn't have a slug" do
        let(:tenant) { NullTenant.new }

        it "raises an error" do
          expect do
            client.publish_changes(
              repo:, dependabot_branch_name: "dependabot", base_commit_sha: "1234567",
              commit_message: "commit", dependency_files: [],
            )
          end.to raise_error(GitHub::Twirp::Error)
        end
      end
    end

    context "not in Proxima", proxima: false do
      it "does not set tenancy headers on the request" do
        client.publish_changes(
          repo:, dependabot_branch_name: "dependabot", base_commit_sha: "1234567",
          commit_message: "commit", dependency_files: [],
        )
        expect(base_client).to have_received(:publish_changes).
          with(anything, {})
      end
    end

    context "with a twirp response error" do
      let(:twirp_error) { Twirp::Error.not_found("test") }

      it "raises a TwirpError" do
        expect do
          client.publish_changes(
            repo:, dependabot_branch_name: "dependabot", base_commit_sha: "1234567",
            commit_message: "commit", dependency_files: [],
          )
        end.to raise_error(GitHub::Twirp::DependabotPullRequests::TwirpError)

        expect(MetricsClient).to have_received(:distribution).with(
          "twirp.github.dependabot_pull_requests.publish_changes",
          anything,
          tags: { response_code: twirp_error.code }
        )
      end
    end

    context "with an error in the API response data" do
      let(:response_error) do
        MonolithTwirp::Dependabot::PullRequests::V1::Error.new(
          type: MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_GIT,
          message: "test",
        )
      end

      it "raises a ServiceError" do
        expect do
          client.publish_changes(
            repo:, dependabot_branch_name: "dependabot", base_commit_sha: "1234567",
            commit_message: "commit", dependency_files: [],
          )
        end.to raise_error(GitHub::Twirp::DependabotPullRequests::ServiceError)

        expect(MetricsClient).to have_received(:distribution).with(
          "twirp.github.dependabot_pull_requests.publish_changes",
          anything,
          tags: { response_code: :ok }
        )
      end
    end
  end

  describe "#create_pull_request" do
    let(:response_error) { nil }
    let(:twirp_error) { nil }
    let(:pull_request) do
      MonolithTwirp::Dependabot::PullRequests::V1::PullRequest.new(
        repository_id: repo.github_id,
        base_ref: "main",
        base_sha: "1234567",
        github_number: 1,
        head_ref: "dependabot",
        head_sha: "2345678",
        state: "open"
      )
    end

    before do
      allow(base_client).to receive(:create_pull_request).
        and_return(Twirp::ClientResp.new(
                     data: MonolithTwirp::Dependabot::PullRequests::V1::CreatePullRequestResponse.new(
                       pull_request:,
                       error: response_error,
                     ),
                     error: twirp_error,
                   ))
    end

    it "returns a created pull request" do # rubocop:disable RSpec/ExampleLength
      api_pull_request = client.create_pull_request(
        repo:, base_branch_name: "main", head_branch_name: "dependabot",
        pr_name: "pr title", pr_description: "pr body",
        labels: [MonolithTwirp::Dependabot::PullRequests::V1::Label.new(name: "dependabot")],
        reviewers: { "reviewers" => %w(user1 user2), "team_reviewers" => %w(team1 team2) },
        assignees: %w(user1 user2),
        milestone_number: nil, dependabot_update_id: nil
      )

      expect(api_pull_request).to eq(pull_request)
      expect(MetricsClient).to have_received(:distribution).with(
        "twirp.github.dependabot_pull_requests.create_pull_request",
        anything,
        tags: { response_code: :ok }
      )
      expect(base_client).to have_received(:create_pull_request) do |req, _metadata|
        expect(req.repository_id).to eq(repo.github_id)
        expect(req.base_branch_name).to eq("main")
        expect(req.head_branch_name).to eq("dependabot")
        expect(req.pr_name).to eq("pr title")
        expect(req.pr_description).to eq("pr body")
        expect(req.labels.map(&:name)).to eq(["dependabot"])
        expect(req.reviewers.users.to_a).to eq(%w(user1 user2))
        expect(req.reviewers.teams.to_a).to eq(%w(team1 team2))
        expect(req.assignees.to_a).to eq(%w(user1 user2))
        expect(req.milestone_number).to eq(0)
        expect(req.dependabot_update_id).to eq(0)
      end
    end

    context "in Proxima", :proxima do
      it "sets tenancy headers on the request" do
        client.create_pull_request(
          repo:, base_branch_name: "main", head_branch_name: "dependabot",
          pr_name: "pr title", pr_description: "pr body",
          labels: [], reviewers: {}, assignees: [], milestone_number: nil, dependabot_update_id: nil
        )
        expect(base_client).to have_received(:create_pull_request).
          with(anything, { headers: { "X-GitHub-Tenant" => tenant.slug } })
      end

      context "when the tenant doesn't have a slug" do
        let(:tenant) { NullTenant.new }

        it "raises an error" do
          expect do
            client.create_pull_request(
              repo:, base_branch_name: "main", head_branch_name: "dependabot",
              pr_name: "pr title", pr_description: "pr body",
              labels: [], reviewers: {}, assignees: [], milestone_number: nil, dependabot_update_id: nil
            )
          end.to raise_error(GitHub::Twirp::Error)
        end
      end
    end

    context "not in Proxima", proxima: false do
      it "does not set tenancy headers on the request" do
        client.create_pull_request(
          repo:, base_branch_name: "main", head_branch_name: "dependabot",
          pr_name: "pr title", pr_description: "pr body",
          labels: [], reviewers: {}, assignees: [], milestone_number: nil, dependabot_update_id: nil
        )
        expect(base_client).to have_received(:create_pull_request).
          with(anything, {})
      end
    end

    context "with a twirp response error" do
      let(:twirp_error) { Twirp::Error.not_found("test") }

      it "raises a TwirpError" do
        expect do
          client.create_pull_request(
            repo:, base_branch_name: "main", head_branch_name: "dependabot",
            pr_name: "pr title", pr_description: "pr body",
            labels: [], reviewers: {}, assignees: [], milestone_number: nil, dependabot_update_id: nil
          )
        end.to raise_error(GitHub::Twirp::DependabotPullRequests::TwirpError)

        expect(MetricsClient).to have_received(:distribution).with(
          "twirp.github.dependabot_pull_requests.create_pull_request",
          anything,
          tags: { response_code: twirp_error.code }
        )
      end
    end

    context "with an error in the API response data" do
      let(:response_error) do
        MonolithTwirp::Dependabot::PullRequests::V1::Error.new(
          type: MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_GIT,
          message: "test",
        )
      end

      it "raises a ServiceError" do
        expect do
          client.create_pull_request(
            repo:, base_branch_name: "main", head_branch_name: "dependabot",
            pr_name: "pr title", pr_description: "pr body",
            labels: [], reviewers: {}, assignees: [], milestone_number: nil, dependabot_update_id: nil
          )
        end.to raise_error(GitHub::Twirp::DependabotPullRequests::ServiceError)

        expect(MetricsClient).to have_received(:distribution).with(
          "twirp.github.dependabot_pull_requests.create_pull_request",
          anything,
          tags: { response_code: :ok }
        )
      end
    end
  end

  describe "#get_ci_status" do
    let(:response_error) { nil }
    let(:twirp_error) { nil }
    let(:statuses) do
      {
        "abc1234" =>
          client.resolve_ci_status_symbol(MonolithTwirp::Dependabot::PullRequests::V1::CiStatus::CI_STATUS_PENDING),
        "def1234" =>
          client.resolve_ci_status_symbol(MonolithTwirp::Dependabot::PullRequests::V1::CiStatus::CI_STATUS_SUCCESS),
      }
    end
    let(:pull_request) { create(:pull_request, repo:) }

    before do
      allow(base_client).to receive(:get_ci_status).
        and_return(Twirp::ClientResp.new(
                     data: MonolithTwirp::Dependabot::PullRequests::V1::GetCiStatusResponse.new(
                       statuses:,
                       error: response_error,
                     ),
                     error: twirp_error,
                   ))
    end

    it "returns CI statuses for shas" do
      api_statuses = client.get_ci_status(repo:, shas: statuses.keys)

      expect(api_statuses).to eq(statuses)
      expect(MetricsClient).to have_received(:distribution).with(
        "twirp.github.dependabot_pull_requests.get_ci_status",
        anything,
        tags: { response_code: :ok }
      )
      expect(base_client).to have_received(:get_ci_status).
        with(MonolithTwirp::Dependabot::PullRequests::V1::GetCiStatusRequest.new(
               repository_id: repo.github_id,
               shas: statuses.keys
             ), anything)
    end

    it "returns an empty hash if no shas are given" do
      expect(client.get_ci_status(repo:, shas: [])).to eq({})
    end

    context "in Proxima", :proxima do
      it "sets tenancy headers on the request" do
        client.get_ci_status(repo:, shas: statuses.keys)
        expect(base_client).to have_received(:get_ci_status).
          with(anything, { headers: { "X-GitHub-Tenant" => tenant.slug } })
      end

      context "when the tenant doesn't have a slug" do
        let(:tenant) { NullTenant.new }

        it "raises an error" do
          expect do
            client.get_ci_status(repo:, shas: statuses.keys)
          end.to raise_error(GitHub::Twirp::Error)
        end
      end
    end

    context "not in Proxima", proxima: false do
      it "does not set tenancy headers on the request" do
        client.get_ci_status(repo:, shas: statuses.keys)
        expect(base_client).to have_received(:get_ci_status).
          with(anything, {})
      end
    end

    context "with a twirp response error" do
      let(:twirp_error) { Twirp::Error.not_found("test") }

      it "raises a TwirpError" do
        expect do
          client.get_ci_status(repo:, shas: statuses.keys)
        end.to raise_error(GitHub::Twirp::DependabotPullRequests::TwirpError)

        expect(MetricsClient).to have_received(:distribution).with(
          "twirp.github.dependabot_pull_requests.get_ci_status",
          anything,
          tags: { response_code: twirp_error.code }
        )
      end
    end

    context "with an error in the API response data" do
      let(:response_error) do
        MonolithTwirp::Dependabot::PullRequests::V1::Error.new(
          type: MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_GIT,
          message: "test",
        )
      end

      it "raises a ServiceError" do
        expect do
          client.get_ci_status(repo:, shas: statuses.keys)
        end.to raise_error(GitHub::Twirp::DependabotPullRequests::ServiceError)

        expect(MetricsClient).to have_received(:distribution).with(
          "twirp.github.dependabot_pull_requests.get_ci_status",
          anything,
          tags: { response_code: :ok }
        )
      end
    end
  end
end
