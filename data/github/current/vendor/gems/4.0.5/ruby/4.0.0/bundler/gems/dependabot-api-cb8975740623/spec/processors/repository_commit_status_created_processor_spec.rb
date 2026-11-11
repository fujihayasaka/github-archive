# frozen_string_literal: true

require "rails_helper"
require_relative "shared_examples/application_processor"

RSpec.describe RepositoryCommitStatusCreatedProcessor do
  include ActiveSupport::Testing::TimeHelpers

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
    hydro_fixture(name: fixture_name,
                  schema: "github.v1.RepositoryCommitStatusCreated")
  end

  let(:repo) do
    FactoryBot.create(:repo, :active, :bump_test,
                      github_id: decoded_payload[:repository_id])
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

  let(:expected_tags) do
    { consumer: "dependabot_api_repository_commit_status_created" }
  end

  before do
    allow(consumer).to receive(:mark_message_as_processed)
    allow(MetricsClient).to receive(:increment)
  end

  describe "configuration" do
    subject(:config) { described_class.options }

    it "is correctly configured" do
      expect(config[:group_id]).
        to eql("dependabot_api_repository_commit_status_created")
      expect(config[:subscribe_to]).
        to eql(/github\.v1\.RepositoryCommitStatusCreated\Z/)
      expect(config[:automatically_mark_as_processed]).to be false
    end
  end

  context "for a CI status update" do
    let(:fixture_name) { :default }

    let!(:pull_request) do
      FactoryBot.create(
        :pull_request, :bump_test,
        repo: repo,
        dependencies: dependencies,
        head_commit_sha: "headcommitsha",
        dependabot_commit_sha: "headcommitsha",
      )
    end

    it_behaves_like "an application processor"

    context "that is not completed" do
      let(:fixture_name) { :pending_event }

      it "doesn't enqueue CI status update jobs" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(UpdatePullRequestCiStatusJob)
      end
    end

    context "that is failure" do
      let(:fixture_name) { :failure_event }

      context "for an account that doesn't auto-merge PRs" do
        it "processes the status update" do
          expect { processor.process_with_consumer(message, consumer) }.
            to have_enqueued_job(UpdatePullRequestCiStatusJob)
        end
      end
    end

    context "with a commit SHA that isn't recognised" do
      before { pull_request.update!(head_commit_sha: "unknown") }

      before { pull_request.update!(dependabot_commit_sha: "unknown") }

      it "doesn't enqueue a CI status update" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(UpdatePullRequestCiStatusJob)
      end
    end

    context "with a commit SHA that is recognised" do
      it "updates the pull request's CI status after a delay" do
        freeze_time do
          expect { processor.process_with_consumer(message, consumer) }.
            to have_enqueued_job(UpdatePullRequestCiStatusJob).
            at(UpdatePullRequestCiStatusJob::DEBOUNCE_PERIOD.from_now).
            with(pull_request: pull_request, refs_to_check: ["headcommitsha"])
        end
      end

      context "with a merged PR" do
        before do
          pull_request.transition_to!(:merged)
        end

        it "doesn't enqueue a CI status update" do
          expect { processor.process_with_consumer(message, consumer) }.
            not_to have_enqueued_job(UpdatePullRequestCiStatusJob)
        end
      end

      context "with a closed PR" do
        before do
          pull_request.transition_to!(:closed)
        end

        it "doesn't enqueue a CI status update" do
          expect { processor.process_with_consumer(message, consumer) }.
            not_to have_enqueued_job(UpdatePullRequestCiStatusJob)
        end
      end

      context "with a PR that has a terminal base commit CI status" do
        before do
          decoded_payload[:commit_sha] = pull_request.base_commit_sha
          pull_request.update!(base_commit_ci_status: GitHub::CheckRun::Conclusion::FAILURE)
        end

        it "doesn't enqueue a CI status update" do
          expect { processor.process_with_consumer(message, consumer) }.
            not_to have_enqueued_job(UpdatePullRequestCiStatusJob)
        end
      end

      context "with a PR that has a non-terminal base commit CI status" do
        before do
          decoded_payload[:commit_sha] = pull_request.base_commit_sha
          pull_request.update!(base_commit_ci_status: GitHub::CheckRun::Status::PENDING)
        end

        it "enqueues a CI status update" do
          expect { processor.process_with_consumer(message, consumer) }.
            to have_enqueued_job(UpdatePullRequestCiStatusJob).
            with(pull_request: pull_request, refs_to_check: [pull_request.base_commit_sha])
        end
      end
    end
  end
end
