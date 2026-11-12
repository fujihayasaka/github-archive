# frozen_string_literal: true

require "rails_helper"
require "spec_helper"

RSpec.describe HandleWebhook::WorkflowRun do
  # These values correspond to fixtures generated from dsp-testing/dependabot-actions-webhook-test
  subject(:action) { described_class.new(webhook_body: webhook_body) }

  let(:github_repo_id) { 410261783 }

  let(:account) { FactoryBot.create(:account) }
  let(:repository) { Factorybot.create(:repo, account: account, github_id: github_repo_id) }
  let(:webhook_body) { payload.deep_symbolize_keys }

  context "when the workflow_run has just been requested" do
    let(:payload) do
      json_fixture("github_webhooks/workflow_run_requested")
    end

    it "does not enqueue a handler job" do
      expect { action.run }.not_to have_enqueued_job(HandleFailedActionRunJob)
    end
  end

  context "when the workflow_run has completed with a conclusion of success" do
    let(:payload) do
      json_fixture("github_webhooks/workflow_run_completed_successfully")
    end

    it "does not enqueue a handler job" do
      expect { action.run }.not_to have_enqueued_job(HandleFailedActionRunJob)
    end
  end

  context "when the workflow_run has completed with a conclusion of failure" do
    let(:payload) do
      json_fixture("github_webhooks/workflow_run_completed_with_errors")
    end

    it "enqueues a handler job" do
      expect { action.run }.to have_enqueued_job(HandleFailedActionRunJob).with(
        workflow_run_id: payload["workflow_run"]["id"]
      )
    end
  end

  context "when the workflow_run has completed with a conclusion of failure, but wasn't triggered by Dependabot" do
    let(:payload) do
      json_fixture("github_webhooks/workflow_run_completed_with_errors").tap do |payload|
        payload["sender"]["login"] = "rando"
      end
    end

    it "does not enqueue a handler job" do
      expect { action.run }.not_to have_enqueued_job(HandleFailedActionRunJob)
    end
  end

  context "when the workflow_run has completed with a conclusion of failure, but wasn't from a dynamic event" do
    let(:payload) do
      json_fixture("github_webhooks/workflow_run_completed_with_errors").tap do |payload|
        payload["workflow_run"]["event"] = "push"
      end
    end

    it "does not enqueue a handler job" do
      expect { action.run }.not_to have_enqueued_job(HandleFailedActionRunJob)
    end
  end

  %w(
    neutral
    cancelled
    timed_out
    action_required
    stale
  ).each do |conclusion|
    context "when the workflow_run has completed with a conclusion of '#{conclusion}'" do
      let(:payload) do
        json_fixture("github_webhooks/workflow_run_completed_with_errors").tap do |payload|
          payload["workflow_run"]["conclusion"] = conclusion
        end
      end

      it "enqueues a handler job" do
        expect { action.run }.to have_enqueued_job(HandleFailedActionRunJob).with(
          workflow_run_id: payload["workflow_run"]["id"]
        )
      end
    end
  end
end
