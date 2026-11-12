# frozen_string_literal: true

require "rails_helper"

RSpec.describe HandleWebhook::PullRequest do
  include ActiveJob::TestHelper

  subject(:action) { described_class.new(webhook_body: webhook_body) }

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:github_repo_url) { github_url + "repositories/#{repo.github_id}" }
  let(:github_pr_url) do
    github_repo_url + "/pulls/#{pull_request.github_number}"
  end

  context "for a Dependabot PR" do
    let(:repo) { FactoryBot.create(:repo, github_id: 88071876) }
    let(:update_config) { FactoryBot.create(:update_config, repo: repo) }
    let(:update_job) do
      FactoryBot.create(:update_job, update_config: update_config)
    end
    let!(:pull_request) do
      FactoryBot.create(
        :pull_request,
        repo: repo,
        update_job: update_job,
        github_number: 10,
      )
    end

    describe "given a 'reopened' webhook" do
      let(:webhook_body) do
        hash = json_fixture("github_webhooks/pull_request_reopened")
        hash.deep_symbolize_keys
      end

      let(:github_pr_data) do
        fixture("github_responses/pull_request_mergeable.json")
      end

      before do
        allow(GitHubHelpers).to receive(:installation_access_token_for)
        stub_request(:get, github_pr_url).
          to_return(status: 200, body: github_pr_data, headers: json_header)
      end

      it "queues up a RebasePullRequestIfNewCommitsJob" do
        perform_enqueued_jobs(only: ResyncPrStateJob) do
          expect { action.run }.
            to have_enqueued_job(RebasePullRequestIfNewCommitsJob).
            with(pull_request: pull_request)
        end
      end

      it "marks the repository as active", feature: :inactivity_pausing do
        repo.update(will_pause_at: 30.days.from_now.utc)

        perform_enqueued_jobs(only: ResyncPrStateJob) do
          expect { action.run }.
            to change { repo.reload.will_pause_at }.
            from(within(1.second).of(30.days.from_now.utc)).to(nil)
        end
      end

      context "when there is an ignored update" do
        before do
          FactoryBot.create(
            :ignore_condition,
            update_config: pull_request.update_config,
            dependency_name: dependency_name,
            version_requirement: version_requirement,
          )
        end

        let(:version_requirement) { "~> 1" }
        let(:dependency_name) { pull_request.updated_dependencies.first.name }

        it "removes the ignored update" do
          perform_enqueued_jobs(only: ResyncPrStateJob) do
            expect { action.run }.to change(IgnoreCondition, :count).to(0)
          end
        end

        context "for a different dependency" do
          let(:dependency_name) { "different" }

          it "doesn't remove the ignored updates" do
            perform_enqueued_jobs(only: ResyncPrStateJob) do
              expect { action.run }.not_to change(IgnoreCondition, :count)
            end
          end
        end

        context "for a different version" do
          let(:version_requirement) { "~> 2" }

          it "doesn't remove the ignored updates" do
            perform_enqueued_jobs(only: ResyncPrStateJob) do
              expect { action.run }.not_to change(IgnoreCondition, :count)
            end
          end
        end

        context "for a non-numeric version" do
          let!(:pull_request) do
            FactoryBot.create(
              :pull_request,
              repo: repo,
              update_job: update_job,
              dependencies: [
                {
                  name: "business",
                  version: "asdfa",
                },
              ],
              github_number: 10,
            )
          end

          it "doesn't remove the ignored updates" do
            perform_enqueued_jobs(only: ResyncPrStateJob) do
              expect { action.run }.not_to change(IgnoreCondition, :count)
              expect { action.run }.not_to raise_error
            end
          end
        end

        context "for a removed transitive dependency" do
          let!(:pull_request) do
            FactoryBot.create(
              :pull_request,
              repo: repo,
              update_job: update_job,
              dependencies: [
                {
                  name: "removed",
                  removed: true,
                },
                {
                  name: "business",
                  version: "1.8.0",
                },
              ],
              github_number: 10,
            )
          end

          before do
            FactoryBot.create(
              :ignore_condition,
              update_config: pull_request.update_config,
              dependency_name: "business",
              version_requirement: "~> 1",
            )
          end

          it "removes the ignored updates for the remaining depenency" do
            perform_enqueued_jobs(only: ResyncPrStateJob) do
              expect { action.run }.to change(IgnoreCondition, :count).
                from(2).to(1)
              expect { action.run }.not_to raise_error

              action.run
              expect(IgnoreCondition.last.dependency_name).to eq("removed")
            end
          end
        end
      end

      context "when there is no status mismatch" do
        it "doesn't transition the pull requests" do
          perform_enqueued_jobs(only: ResyncPrStateJob) do
            expect { action.run }.
              not_to change { pull_request.last_transition(force_reload: true) }
          end
        end
      end

      context "when there is a status mismatch" do
        before { pull_request.transition_to!(:closed) }

        it "transitions the pull requests" do
          perform_enqueued_jobs(only: ResyncPrStateJob) do
            expect { action.run }.
              to change { pull_request.current_state(force_reload: true) }.
              from("closed").to("up_to_date")
          end
        end
      end
    end

    describe "given a 'closed' webhook" do
      let(:webhook_body) do
        hash = json_fixture("github_webhooks/pull_request_closed")
        hash.deep_symbolize_keys
      end
      let(:pr_comments_url) do
        github_repo_url + "/issues/#{pull_request.github_number}/comments"
      end
      let(:github_pr_data) do
        fixture("github_responses/pull_request_closed.json")
      end

      let(:previous_comments) { "[]" }

      let(:dummy_commenter) do
        instance_double(CreateVersionSkipComment, run: nil)
      end

      before do
        allow(GitHubHelpers).to receive(:installation_access_token_for)
        allow(CreateVersionSkipComment).to receive(:new).
          and_return(dummy_commenter)
        stub_request(:get, github_pr_url).
          to_return(status: 200, body: github_pr_data, headers: json_header)
        stub_request(:get, pr_comments_url + "?per_page=100").
          to_return(status: 200, body: previous_comments, headers: json_header)
      end

      it "runs CreateVersionSkipComment on the pull request" do
        expect(dummy_commenter).to receive(:run)
        perform_enqueued_jobs(only: ResyncPrStateJob) do
          action.run
        end
      end

      it "marks the repository as active", feature: :inactivity_pausing do
        repo.update(will_pause_at: 30.days.from_now.utc)

        perform_enqueued_jobs(only: ResyncPrStateJob) do
          expect { action.run }.
            to change { repo.reload.will_pause_at }.
            from(within(1.second).of(30.days.from_now.utc)).to(nil)
        end
      end

      context "when a rate limit abuse is detected" do
        before do
          allow(dummy_commenter).
            to receive(:run).
            and_raise(Octokit::AbuseDetected)
        end

        it "schedules a retry" do
          perform_enqueued_jobs(only: ResyncPrStateJob) do
            expect { action.run }.
              to have_enqueued_job(CreateVersionSkipCommentJob).
              with(pull_request: pull_request)
          end
        end
      end

      it "transitions the pull requests" do
        perform_enqueued_jobs(only: ResyncPrStateJob) do
          expect { action.run }.
            to change { pull_request.current_state(force_reload: true) }.
            from("up_to_date").to("closed")
        end
      end

      it "enqueues a branch deletion job" do
        perform_enqueued_jobs(only: ResyncPrStateJob) do
          expect { action.run }.
            to have_enqueued_job(DeletePullRequestBranchJob).
            with(pull_request: pull_request)
        end
      end

      context "when the PR was closed whilst asking for an ignore" do
        let(:previous_comments) do
          fixture("github_responses/issue_comments_requesting_ignore.json")
        end

        it "transitions the pull requests" do
          perform_enqueued_jobs(only: ResyncPrStateJob) do
            expect { action.run }.
              to change { pull_request.current_state(force_reload: true) }.
              from("up_to_date").to("closed")
          end
        end

        it "enqueues a branch deletion job" do
          # TODO
          expect { action.run }.
            to have_enqueued_job(DeletePullRequestBranchJob).
            with(pull_request: pull_request)
        end

        it "does not create a version skip comment on the pull request" do
          allow(CreateVersionSkipComment).to receive(:new).and_call_original
          perform_enqueued_jobs(only: ResyncPrStateJob) do
            action.run
          end
          expect(WebMock).not_to have_requested(:post, pr_comments_url)
        end
      end

      context "when closed by pushing the master branch to it" do
        let(:webhook_body) do
          hash = json_fixture("github_webhooks/pull_request_closed")
          hash.deep_symbolize_keys
        end
        let(:github_pr_data) do
          fixture("github_responses/pull_request_closed_null.json")
        end

        it "doesn't comment on the pull request" do
          perform_enqueued_jobs(only: ResyncPrStateJob) do
            action.run
          end
          expect(WebMock).not_to have_requested(:post, pr_comments_url)
        end

        it "transitions the pull requests" do
          perform_enqueued_jobs(only: ResyncPrStateJob) do
            expect { action.run }.
              to change { pull_request.current_state(force_reload: true) }.
              from("up_to_date").to("closed")
          end
        end
      end

      context "when the PR was merged" do
        let(:webhook_body) do
          hash = json_fixture("github_webhooks/pull_request_merged")
          hash.deep_symbolize_keys
        end

        before { github_pr_data.gsub!(/"merged": false/, "\"merged\": true") }

        it "doesn't comment on the pull request" do
          perform_enqueued_jobs(only: ResyncPrStateJob) do
            action.run
          end
          expect(WebMock).not_to have_requested(:post, pr_comments_url)
        end

        it "transitions the pull requests" do
          perform_enqueued_jobs(only: ResyncPrStateJob) do
            expect { action.run }.
              to change { pull_request.current_state(force_reload: true) }.
              from("up_to_date").to("merged")
          end
        end

        it "marks the repository as active", feature: :inactivity_pausing do
          repo.update(will_pause_at: 30.days.from_now.utc)

          perform_enqueued_jobs(only: ResyncPrStateJob) do
            expect { action.run }.
              to change { repo.reload.will_pause_at }.
              from(within(1.second).of(30.days.from_now.utc)).to(nil)
          end
        end
      end

      context "when the PR was closed by Dependabot" do
        let(:webhook_body) do
          hash =
            json_fixture("github_webhooks/pull_request_closed_by_dependabot")
          hash.deep_symbolize_keys
        end

        it "doesn't comment on the pull request" do
          perform_enqueued_jobs(only: ResyncPrStateJob) do
            action.run
          end
          expect(WebMock).not_to have_requested(:post, pr_comments_url)
        end

        it "does not mark the repository as active" do
          repo.update(will_pause_at: 30.days.from_now.utc)

          perform_enqueued_jobs(only: ResyncPrStateJob) do
            expect { action.run }.
              not_to change { repo.reload.will_pause_at }.
              from(within(1.second).of(30.days.from_now.utc))
          end
        end
      end
    end
  end
end
