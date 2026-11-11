# frozen_string_literal: true

require "rails_helper"

RSpec.describe Routes::GitHubWebhooks::Create do
  subject(:instance) { described_class.new(context) }

  let(:context) { { request: request } }
  let(:request) do
    instance_double(ActionDispatch::Request, headers: headers, params: params)
  end
  let(:headers) { { "X-GitHub-Event" => webhook_action } }
  let(:params) { webhook_body.deep_symbolize_keys }

  context "without a webhook action" do
    let(:webhook_action) { nil }
    let(:webhook_body) { {} }

    it { is_expected.to respond_with_status(400) }
    it { is_expected.to respond_with_body_that_matches(/No X-GitHub-Event/) }
  end

  context "with an unrecognised webhook action" do
    let(:webhook_action) { "who_knows" }
    let(:webhook_body) { {} }

    it { is_expected.to respond_with_status(204) }

    it "logs the webhooks" do
      expect(Rails.logger).to receive(:info).with(/#{webhook_action}/)
      instance.call
    end
  end

  context "with a ping" do
    let(:webhook_action) { "ping" }
    let(:webhook_body) { {} }

    it { is_expected.to respond_with_status(200) }
    it { is_expected.to respond_with_body_that_matches("pong") }
  end

  context "with an event that is handled" do
    let(:webhook_action) { "pull_request" }
    let(:webhook_body) { json_fixture("github_webhooks/pull_request_opened") }
    let(:dummy_webhook_handler) { instance_double(HandleWebhook::PullRequest) }

    it "increments a metric" do
      allow(instance.tracer).to receive(:in_span).and_call_original
      allow(HandleWebhook::PullRequest).
        to receive(:new).
        and_return(dummy_webhook_handler)
      allow(dummy_webhook_handler).to receive(:run)

      expect(MetricsClient).
        to receive(:increment).
        with("webhook.handled", tags: { event: "pull_request" })

      instance.call

      expect(instance.tracer).to have_received(:in_span).with(
        "Routes::GitHubWebhooks::Create#call",
        attributes: { "gh.webhook.event_type" => "pull_request" }
      )
      expect(instance.tracer).to have_received(:in_span).
        with("#{dummy_webhook_handler.class.name}#run")
    end
  end

  context "with an installation" do
    let(:webhook_action) { "installation" }
    let(:webhook_body) do
      json_fixture("github_webhooks/installation_created")
    end

    it { is_expected.to respond_with_status(204) }
  end

  context "with a pull_request" do
    let(:webhook_action) { "pull_request" }
    let(:webhook_body) { json_fixture("github_webhooks/pull_request_opened") }
    let(:dummy_webhook_handler) { instance_double(HandleWebhook::PullRequest) }

    it { is_expected.to respond_with_status(204) }

    it "delegates to HandleWebhook::PullRequest" do
      expect(HandleWebhook::PullRequest).
        to receive(:new).
        and_return(dummy_webhook_handler)
      expect(dummy_webhook_handler).to receive(:run)

      instance.call
    end
  end

  context "with an installation_repositories" do
    let(:webhook_action) { "installation_repositories" }
    let(:webhook_body) do
      json_fixture(
        "github_webhooks/installation_repositories_removed",
      )
    end

    it { is_expected.to respond_with_status(204) }
  end

  context "with an issue_comment" do
    let(:webhook_action) { "issue_comment" }
    let(:webhook_body) { json_fixture("github_webhooks/issue_comment") }
    let(:dummy_webhook_handler) { instance_double(HandleWebhook::IssueComment) }

    it { is_expected.to respond_with_status(204) }

    it "delegates to HandleWebhook::IssueComment" do
      expect(HandleWebhook::IssueComment).
        to receive(:new).
        and_return(dummy_webhook_handler)
      expect(dummy_webhook_handler).to receive(:run)

      instance.call
    end
  end

  context "with an check_suite" do
    let(:webhook_action) { "check_suite" }
    let(:webhook_body) { json_fixture("github_webhooks/check_suite_completed") }
    let(:dummy_webhook_handler) { instance_double(HandleWebhook::CheckSuite) }

    it { is_expected.to respond_with_status(204) }

    it "delegates to HandleWebhook::CheckSuite" do
      expect(HandleWebhook::CheckSuite).
        to receive(:new).
        and_return(dummy_webhook_handler)
      expect(dummy_webhook_handler).to receive(:run)

      instance.call
    end
  end

  context "with a pull_request_review_comment" do
    let(:webhook_action) { "pull_request_review_comment" }
    let(:webhook_body) do
      json_fixture("github_webhooks/pull_request_review_comment")
    end
    let(:dummy_webhook_handler) { instance_double(HandleWebhook::IssueComment) }

    it { is_expected.to respond_with_status(204) }

    it "delegates to HandleWebhook::IssueComment" do
      expect(HandleWebhook::IssueComment).
        to receive(:new).
        and_return(dummy_webhook_handler)
      expect(dummy_webhook_handler).to receive(:run)

      instance.call
    end
  end

  context "with a pull_request_review" do
    let(:webhook_action) { "pull_request_review" }
    let(:webhook_body) do
      json_fixture("github_webhooks/pull_request_review")
    end
    let(:dummy_webhook_handler) { instance_double(HandleWebhook::PullRequestReview) }

    it { is_expected.to respond_with_status(204) }

    it "delegates to HandleWebhook::PullRequestReview" do
      expect(HandleWebhook::PullRequestReview).
        to receive(:new).
        and_return(dummy_webhook_handler)
      expect(dummy_webhook_handler).to receive(:run)

      instance.call
    end
  end

  context "with a check_run" do
    let(:webhook_action) { "check_run" }
    let(:webhook_body) do
      json_fixture("github_webhooks/check_run_rerequested")
    end
    let(:dummy_webhook_handler) { instance_double(HandleWebhook::CheckRun) }

    it { is_expected.to respond_with_status(204) }

    it "delegates to HandleWebhook::CheckRun" do
      expect(HandleWebhook::CheckRun).
        to receive(:new).
        and_return(dummy_webhook_handler)
      expect(dummy_webhook_handler).to receive(:run)

      instance.call
    end
  end

  context "with a workflow_run" do
    let(:webhook_action) { "workflow_run" }
    let(:webhook_body) do
      json_fixture("github_webhooks/workflow_run_requested")
    end
    let(:dummy_webhook_handler) { instance_double(HandleWebhook::WorkflowRun) }

    it { is_expected.to respond_with_status(204) }

    it "delegates to HandleWebhook::WorkflowRun" do
      expect(HandleWebhook::WorkflowRun).
        to receive(:new).
        and_return(dummy_webhook_handler)
      expect(dummy_webhook_handler).to receive(:run)

      instance.call
    end
  end
end
