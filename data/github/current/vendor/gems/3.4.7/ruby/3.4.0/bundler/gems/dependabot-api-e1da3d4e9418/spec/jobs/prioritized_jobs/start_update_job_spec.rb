# frozen_string_literal: true

require "rails_helper"
require "dependabot/dependency_file"

RSpec.describe PrioritizedJobs::StartUpdateJob do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:installation_id) { 1001 }
  let(:account) do
    FactoryBot.create(
      :account, :active,
      installation_id: installation_id,
      github_login: "old_name",
      github_id: 27347476,
    )
  end

  let(:repo_github_id) { 88632334 }
  let(:repo) do
    FactoryBot.create(
      :repo, :active,
      account: account,
      github_id: repo_github_id,
      name: "old_repo_name",
    )
  end

  let(:update_config) { repo.update_configs.last }

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_repo) { fixture("github_responses/repo.json") }
  let(:github_url) { "https://api.github.com/" }
  let(:repo_url) { github_url + "repositories/#{repo.github_id}" }

  let(:install_access_token_url) do
    "#{github_url}app/installations/#{installation_id}/access_tokens"
  end

  let(:install_access_token) do
    erb_fixture("github_responses/installation_access_token.json")
  end

  let(:mock_run_updater) { instance_double(RunUpdater::Actions, run: nil) }
  let(:redis) { Dependabot.redis }

  let(:repo_settings) do
    {
      actions_fully_enabled: true,
      dependabot_self_hosted_enabled: false,
    }
  end

  before do
    # Clear out cached access tokens
    redis.flushdb

    stub_request(:get, repo_url).
      to_return(status: 200, body: github_repo, headers: json_header)
    stub_request(:post, install_access_token_url).
      with(body: anything).
      to_return(
        status: 200,
        body: install_access_token,
        headers: json_header,
      )
    allow(RunUpdater::Actions).
      to receive(:new).
      and_return(mock_run_updater)
  end

  describe "::perform_later" do
    let(:perform_later) do
      described_class.perform_later(update_job)
    end

    UpdateJob::P1_TRIGGER_TYPES.each do |trigger|
      context "with a #{trigger} update job" do
        let!(:update_job) do
          FactoryBot.create(:update_job,
                            update_config: update_config,
                            trigger_type: trigger)
        end

        context "when no actions runs have been performed" do
          it "enqueues a job in the p3 queue" do
            expect { perform_later }.
              to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
              on_queue("actions_dynamic_workflow_p3").
              with(update_job)
          end
        end

        context "when actions runs have been performed" do
          before do
            UpdateJob.create!(
              update_config_id: update_config.id,
              trigger_type: trigger,
              actions_workflow_run_id: 10000
            )
          end

          it "enqueues a job in the p1 queue" do
            expect { perform_later }.
              to have_enqueued_job(PrioritizedJobs::StartUpdateJob::High).
              on_queue("actions_dynamic_workflow_p1").
              with(update_job)
          end
        end
      end
    end

    UpdateJob::P2_TRIGGER_TYPES.each do |trigger|
      context "with a #{trigger} update job" do
        let!(:update_job) do
          FactoryBot.create(:update_job,
                            update_config: update_config,
                            trigger_type: trigger)
        end

        context "when no actions runs have been performed" do
          it "enqueues a job in the p3 queue" do
            expect { perform_later }.
              to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
              on_queue("actions_dynamic_workflow_p3").
              with(update_job)
          end
        end

        context "when actions runs have been performed" do
          before do
            UpdateJob.create!(
              update_config_id: update_config.id,
              trigger_type: trigger,
              actions_workflow_run_id: 10000
            )
          end

          it "enqueues a job in the p2 queue" do
            expect { perform_later }.
              to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Default).
              on_queue("actions_dynamic_workflow_p2").
              with(update_job)
          end
        end
      end
    end

    UpdateJob::P4_TRIGGER_TYPES.each do |trigger|
      context "with a #{trigger} update job" do
        let!(:update_job) do
          FactoryBot.create(:update_job,
                            update_config: update_config,
                            trigger_type: trigger)
        end

        context "when no actions runs have been performed" do
          it "enqueues a job in the p3 queue" do
            expect { perform_later }.
              to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
              on_queue("actions_dynamic_workflow_p3").
              with(update_job)
          end
        end

        context "when actions runs have been performed" do
          before do
            UpdateJob.create!(
              update_config_id: update_config.id,
              trigger_type: trigger,
              actions_workflow_run_id: 10000
            )
          end

          it "enqueues a job in the p4 queue" do
            expect { perform_later }.
              to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Graph).
              on_queue("actions_dynamic_workflow_p4").
              with(update_job)
          end
        end
      end
    end
  end
end
