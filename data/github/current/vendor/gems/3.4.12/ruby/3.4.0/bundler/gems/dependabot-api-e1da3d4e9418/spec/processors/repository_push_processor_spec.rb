# frozen_string_literal: true

require "rails_helper"
require_relative "shared_examples/application_processor"

RSpec.describe RepositoryPushProcessor do
  let(:processor) { described_class.new }

  let(:consumer) do
    Dependabot.hydro_consumer(processor.options)
  end

  let(:message) do
    instance_double(
      Hydro::Consumer::ConsumerMessage,
      value: decoded_payload,
      timestamp: Time.now.utc,
      offset: 0,
      partition: 0,
      topic: "mock",
      headers: {},
    )
  end

  let(:decoded_payload) do
    hydro_fixture(name: fixture_name, schema: "github.v1.RepositoryPush")
  end

  let(:expected_tags) do
    { consumer: "dependabot_api_repository_push" }
  end

  before do
    allow(consumer).to receive(:mark_message_as_processed)
    allow(MetricsClient).to receive(:increment)
  end

  describe "configuration" do
    subject(:config) { described_class.options }

    it "is correctly configured" do
      expect(config[:group_id]).
        to eql("dependabot_api_repository_push")
      expect(config[:subscribe_to]).
        to eql(/github\.v1\.RepositoryPush\Z/)
      expect(config[:automatically_mark_as_processed]).to be false
    end
  end

  context "for a push to the default branch" do
    let(:fixture_name) { "push_main" }

    it_behaves_like "an application processor"

    context "with a bundler dependabot PR open" do
      let(:repo) { FactoryBot.create(:repo, :active, :bump_test) }
      let(:update_config) { repo.update_configs.last }
      let(:update_job) do
        FactoryBot.create(:update_job, update_config: update_config)
      end
      let!(:pull_request) do
        FactoryBot.create(
          :pull_request,
          repo: repo,
          update_job: update_job,
          github_number: 21,
        )
      end

      context "for a change to the dependency files that affects monitored files" do
        before { update_config.update!(monitored_files: ["/Gemfile", "/Gemfile.lock"]) }

        it "queues up a CheckPullRequestForConflictsJob" do
          expect { processor.process_with_consumer(message, consumer) }.
            to have_enqueued_job(CheckPullRequestForConflictsJob).
            with(
              pull_request: pull_request,
              event_source: "hydro.repository_push",
              manual: false,
            )
        end

        context "when the repo's name has changed" do
          before { decoded_payload[:repository][:name] = "changed" }

          it "updates the repo" do
            expect { processor.process_with_consumer(message, consumer) }.
              to change { repo.reload.name }.
              to("changed")
          end
        end
      end

      context "for an unrelated change" do
        let(:fixture_name) { "push_main_unrelated" }

        it "doesn't hit GitHub" do
          expect(Octokit::Client).not_to receive(:new)
          expect { processor.process_with_consumer(message, consumer) }.
            not_to have_enqueued_job(CheckPullRequestForConflictsJob)
        end
      end

      context "for an unconfigured package manager change" do
        let(:fixture_name) { "push_main_package_json" }

        it "doesn't enqueue rebase" do
          expect(Octokit::Client).not_to receive(:new)
          expect { processor.process_with_consumer(message, consumer) }.
            not_to have_enqueued_job(CheckPullRequestForConflictsJob)
        end
      end

      context "for a different package manager change" do
        let(:fixture_name) { "push_main_package_json" }

        it "doesn't enqueue rebase of the bundler PR" do
          FactoryBot.create(
            :update_config, :active,
            repo: repo,
            package_manager: "npm_and_yarn",
          )

          expect(Octokit::Client).not_to receive(:new)
          expect { processor.process_with_consumer(message, consumer) }.
            not_to have_enqueued_job(CheckPullRequestForConflictsJob)
        end
      end
    end

    context "for a push to a actions workflow file with an open PR" do
      let(:fixture_name) { "push_main_workflow" }
      let(:repo) do
        FactoryBot.create(:repo, :bump_test, default_branch: "main")
      end
      let(:update_config) do
        FactoryBot.create(
          :update_config, :active,
          repo: repo,
          package_manager: "github_actions",
          monitored_files: ["/.github/workflows/test.yml"]
        )
      end
      let(:update_job) do
        FactoryBot.create(:update_job, update_config: update_config)
      end
      let!(:pull_request) do
        FactoryBot.create(
          :pull_request,
          repo: repo,
          update_job: update_job,
          github_number: 21,
        )
      end

      it "does not queue up a CheckPullRequestForConflictsJob" do
        expect { processor.process_with_consumer(message, consumer) }.
          to have_enqueued_job(CheckPullRequestForConflictsJob).
          with(
            pull_request: pull_request,
            event_source: "hydro.repository_push",
            manual: false,
          )
      end
    end

    context "for a push to a non-existent repo" do
      it "no-ops" do
        expect(Octokit::Client).not_to receive(:new)
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(CheckPullRequestForConflictsJob)
      end
    end

    context "for a push to an inactive repo" do
      let!(:repo) { FactoryBot.create(:repo, :inactive, github_id: 88632334) }

      it "no-ops" do
        expect(Octokit::Client).not_to receive(:new)
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(CheckPullRequestForConflictsJob)
      end
    end

    context "when the repository is paused", feature: :inactivity_pausing do
      let(:repo) do
        FactoryBot.create(:repo, :bump_test, :currently_paused)
      end
      let(:update_config) do
        FactoryBot.create(
          :update_config, :bump_test, :active,
          repo: repo,
          package_manager: "bundler",
          monitored_files: ["/Gemfile", "/Gemfile.lock"]
        )
      end
      let(:update_job) do
        FactoryBot.create(:update_job, update_config: update_config)
      end
      let!(:pull_request) do
        FactoryBot.create(
          :pull_request,
          repo: repo,
          update_job: update_job,
          github_number: 21,
        )
      end

      context "when there is a push on the default branch" do
        it "still updates updates the repository's details " do
          decoded_payload[:repository][:name] = "changed"

          expect { processor.process_with_consumer(message, consumer) }.
            to change { repo.reload.name }.
            to("changed")
        end

        it "does not check Pull Requests for conflict" do
          expect { processor.process_with_consumer(message, consumer) }.
            not_to have_enqueued_job(CheckPullRequestForConflictsJob)
        end

        it "does not retry previously failed jobs" do
          FactoryBot.create(:update_job, :processed_with_errors, update_config: update_config)

          expect { processor.process_with_consumer(message, consumer) }.
            not_to have_enqueued_job

          expect(MetricsClient).not_to have_received(:increment).with(
            "retry_after_dependency_file_change",
            tags: anything
          )
        end
      end

      context "when there is a push on a Dependabot PR branch" do
        let(:fixture_name) { "push_dependabot_branch" }
        let(:head_commit_sha) { "914a7a0d29226ebe35c83e4f599d0229e97e05a8" }

        let!(:pull_request) do
          FactoryBot.create(
            :pull_request,
            repo: repo,
            update_job: update_job,
            github_number: 21,
            head_commit_sha: head_commit_sha,
          )
        end

        it "updates the head commit of any relevant PRs" do
          expect { processor.process_with_consumer(message, consumer) }.
            to change { pull_request.reload.head_commit_sha }.
            to("96f4a1df9a76f3eb212ac6a8828d799abceb8141")
        end

        it "enqueues a job to set the ci_status for the new commit" do
          expect { processor.process_with_consumer(message, consumer) }.
            to have_enqueued_job(UpdatePullRequestCiStatusJob).
            with(
              pull_request_id: pull_request.id,
              refs_to_check: ["96f4a1df9a76f3eb212ac6a8828d799abceb8141"],
            )
        end
      end
    end
  end

  context "for a push to a non-default branch" do
    let(:fixture_name) { "push_feature_branch" }
    let!(:pull_request) do
      FactoryBot.create(
        :pull_request,
        repo: repo,
        update_job: update_job,
        github_number: 21,
      )
    end
    let(:update_job) do
      FactoryBot.create(:update_job, update_config: update_config)
    end
    let(:update_config) { repo.update_configs.last }
    let(:repo) { FactoryBot.create(:repo, :active, :bump_test) }

    it_behaves_like "an application processor"

    it "no-ops" do
      expect(Octokit::Client).not_to receive(:new)
      expect { processor.process_with_consumer(message, consumer) }.
        not_to have_enqueued_job(CheckPullRequestForConflictsJob)
    end

    context "that is the target branch for an updated config" do
      before { update_config.update!(target_branch: "feature_branch") }

      context "for a change to the dependency files that affects monitored files" do
        before { update_config.update!(monitored_files: ["/Gemfile", "/Gemfile.lock"]) }

        it "queues up a CheckPullRequestForConflictsJob" do
          expect { processor.process_with_consumer(message, consumer) }.
            to have_enqueued_job(CheckPullRequestForConflictsJob).
            with(
              pull_request: pull_request,
              event_source: "hydro.repository_push",
              manual: false,
            )
        end
      end

      context "for a change to the dependency files that does not affect monitored files" do
        it "does not queue up a CheckPullRequestForConflictsJob" do
          expect { processor.process_with_consumer(message, consumer) }.
            not_to have_enqueued_job(CheckPullRequestForConflictsJob)
        end
      end
    end

    context "that is a dependabot PR branch" do
      let(:fixture_name) { "push_dependabot_branch" }

      let!(:pull_request) do
        FactoryBot.create(
          :pull_request,
          repo: repo,
          update_job: update_job,
          github_number: 21,
          head_commit_sha: head_commit_sha,
        )
      end

      context "with a pull request at that head commit" do
        let(:head_commit_sha) { "914a7a0d29226ebe35c83e4f599d0229e97e05a8" }

        it "updates the head commit of any relevant PRs" do
          expect { processor.process_with_consumer(message, consumer) }.
            to change { pull_request.reload.head_commit_sha }.
            to("96f4a1df9a76f3eb212ac6a8828d799abceb8141")
        end

        it "enqueues a job to set the ci_status for the new commit" do
          expect { processor.process_with_consumer(message, consumer) }.
            to have_enqueued_job(UpdatePullRequestCiStatusJob).
            with(
              pull_request_id: pull_request.id,
              refs_to_check: ["96f4a1df9a76f3eb212ac6a8828d799abceb8141"],
            )
        end

        context "for a different repo" do
          let(:repo) { FactoryBot.create(:repo, :active, :business) }

          it "doesn't update the pull request" do
            expect { processor.process_with_consumer(message, consumer) }.
              not_to change { pull_request.reload.head_commit_sha }
          end
        end

        context "with a randomly-prefixed branch name" do
          before do
            decoded_payload[:ref] = "refs/heads/a32fdependabot/bundler/webmock"
          end

          it "updates the head commit of any relevant PRs" do
            expect { processor.process_with_consumer(message, consumer) }.
              to change { pull_request.reload.head_commit_sha }.
              to("96f4a1df9a76f3eb212ac6a8828d799abceb8141")
          end
        end
      end

      context "with a pull request at a different head commit" do
        let(:head_commit_sha) { "814a7a0d29226ebe35c83e4f599d0229e97e05a8" }

        it "doesn't update the pull request" do
          expect { processor.process_with_consumer(message, consumer) }.
            not_to change { pull_request.reload.head_commit_sha }
        end
      end
    end

    context "that is a dependabot PR branch using dashes" do
      let(:fixture_name) { "push_dependabot_branch_dashes" }

      let!(:pull_request) do
        FactoryBot.create(
          :pull_request,
          repo: repo,
          update_job: update_job,
          github_number: 21,
          head_commit_sha: head_commit_sha,
        )
      end

      context "with a pull request at that head commit" do
        let(:head_commit_sha) { "914a7a0d29226ebe35c83e4f599d0229e97e05a8" }

        it "updates the head commit of any relevant PRs" do
          expect { processor.process_with_consumer(message, consumer) }.
            to change { pull_request.reload.head_commit_sha }.
            to("96f4a1df9a76f3eb212ac6a8828d799abceb8141")
        end
      end
    end
  end
end
