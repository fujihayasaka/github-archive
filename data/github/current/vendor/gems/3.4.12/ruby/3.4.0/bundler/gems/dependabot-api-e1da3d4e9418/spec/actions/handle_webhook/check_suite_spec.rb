# frozen_string_literal: true

require "rails_helper"

RSpec.describe HandleWebhook::CheckSuite do
  subject(:action) { described_class.new(webhook_body: webhook_body) }

  let!(:pull_request) do
    FactoryBot.create(
      :pull_request, :bump_test,
      dependencies: dependencies,
      head_commit_sha: "headcommitsha",
      dependabot_commit_sha: "headcommitsha",
    )
  end
  let(:dependencies) do
    [
      {
        "name" => "business",
        "version" => "1.8.0",
        "previous_version" => "1.3.0",
        "requirements" => [],
        "previous_requirements" => [],
        "package_manager" => "bundler",
      },
    ]
  end

  context "for a CI status update" do
    let(:webhook_body) do
      hash = json_fixture("github_webhooks/check_suite_completed")
      hash["check_suite"]["app"]["name"] = "Hound"
      hash.deep_symbolize_keys
    end

    context "that is success" do
      let(:webhook_body) do
        hash = json_fixture("github_webhooks/check_suite_completed")
        hash["check_suite"]["app"]["name"] = "Hound"
        hash["check_suite"]["conclusion"] = "success"
        hash.deep_symbolize_keys
      end

      context "for an account that doesn't auto-merge PRs" do
        it "doesn't enqueue a merge check" do
          expect { action.run }.not_to have_enqueued_job(MergePullRequestJob)
        end

        it "does not enqueue a failure comment" do
          expect { action.run }.
            not_to have_enqueued_job(CreateCheckOrStatusFailureCommentJob)
        end

        context "with a PR for which a merge has been explicitly requested" do
          before { pull_request.update!(merge_requested: true) }

          it "enqueues a merge check" do
            expect { action.run }.
              to have_enqueued_job(MergePullRequestJob).
              with(pull_request: pull_request)
          end
        end
      end

      context "with a commit SHA that isn't recognised" do
        before { pull_request.update!(head_commit_sha: "unknown") }

        before { pull_request.update!(dependabot_commit_sha: "unknown") }

        it "doesn't enqueue a merge check" do
          expect { action.run }.not_to have_enqueued_job(MergePullRequestJob)
        end
      end
    end

    context "that is failure" do
      let(:webhook_body) do
        hash = json_fixture("github_webhooks/check_suite_completed")
        hash["check_suite"]["app"]["name"] = "Hound"
        hash["check_suite"]["conclusion"] = "failure"
        hash.deep_symbolize_keys
      end

      context "for an account that doesn't auto-merge PRs" do
        it "doesn't enqueue a failure comment" do
          expect { action.run }.
            not_to have_enqueued_job(CreateCheckOrStatusFailureCommentJob)
        end

        context "with a PR for which a merge has been explicitly requested" do
          before { pull_request.update!(merge_requested: true) }

          it "enqueues a failure comment" do
            expect { action.run }.
              to have_enqueued_job(CreateCheckOrStatusFailureCommentJob).
              with(pull_request: pull_request)
          end
        end
      end
    end

    context "that isn't for a Dependabot branch" do
      let(:webhook_body) do
        hash = json_fixture("github_webhooks/check_suite_completed")
        hash["check_suite"]["app"]["name"] = "Travis CI"
        hash["check_suite"]["head_branch"] = "master"
        hash.deep_symbolize_keys
      end

      before do
        allow(PullRequest).to receive(:for_repo_github_id)
      end

      it "does not hit the database" do
        action.run
        expect(PullRequest).not_to have_received(:for_repo_github_id)
      end

      it "does not enqueue a CI status job" do
        expect { action.run }.
          not_to have_enqueued_job(UpdatePullRequestCiStatusJob)
      end
    end

    context "with a commit SHA that isn't recognised" do
      before { pull_request.update!(head_commit_sha: "unknown") }

      before { pull_request.update!(dependabot_commit_sha: "unknown") }

      it "doesn't enqueue a CI status update" do
        expect { action.run }.
          not_to have_enqueued_job(UpdatePullRequestCiStatusJob)
      end
    end

    context "with a commit SHA that is recognised" do
      it "updates the pull request's CI status" do
        expect { action.run }.
          to have_enqueued_job(UpdatePullRequestCiStatusJob).
          with(pull_request: pull_request, refs_to_check: ["headcommitsha"])
      end
    end
  end
end
