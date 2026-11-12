# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/github_webhooks", type: :request do
  describe "POST /github_webhooks" do
    let(:webhook_secret) { Prius.get(:github_integration_webhook_secret) }
    let(:headers) do
      signature = GitHubHelpers.webhook_signature(request_body, webhook_secret)
      {
        "X-GitHub-Event" => event_type,
        "X-Hub-Signature" => signature,
        "Content-Type" => "application/json",
      }
    end

    describe "given a ping" do
      let(:event_type) { "ping" }
      let(:request_body) { "{}" }

      it "pongs" do
        post "/github_webhooks", params: request_body, headers: headers
        expect(response).to be_successful
        expect(response.body).to match("pong")
      end
    end

    describe "given an issue_comment" do
      let(:event_type) { "issue_comment" }
      let(:request_body) { fixture("github_webhooks/issue_comment.json") }

      context "with a valid webhook signature" do
        let(:webhook_handler) { instance_double(HandleWebhook::IssueComment) }

        it "delegates to HandleWebhook::IssueComment" do
          expect(HandleWebhook::IssueComment).
            to receive(:new).
            and_return(webhook_handler)
          expect(webhook_handler).to receive(:run)

          post "/github_webhooks", params: request_body, headers: headers

          expect(response).to be_no_content
        end
      end

      context "with an invalid webhook signature" do
        let(:webhook_secret) { "invalid secret" }

        it "fails" do
          expect(HandleWebhook::IssueComment).not_to receive(:new)
          post "/github_webhooks", params: request_body, headers: headers
          expect(response).to be_forbidden
        end
      end
    end

    describe "for the actions deployment" do
      let(:event_type) { "ping" }
      let(:request_body) { "{}" }

      def with_stubbed_actions_deployment
        allow(Prius).to receive(:get).and_call_original
        allow(Prius).to receive(:get).with(:actions_deployment).and_return(true)
        Rails.application.reload_routes!
        yield
      ensure
        allow(Prius).to receive(:get).with(:actions_deployment).and_call_original
        Rails.application.reload_routes!
      end

      it "responds with a not found error" do
        with_stubbed_actions_deployment do
          post "/github_webhooks", params: request_body, headers: headers
          expect(response).to be_not_found
        end
      end
    end
  end

  describe "POST /github_webhooks/discard" do
    let(:event_type) { "ping" }
    let(:request_body) { "{}" }
    let(:webhook_secret) { Prius.get(:github_integration_webhook_secret) }
    let(:headers) do
      signature = GitHubHelpers.webhook_signature(request_body, webhook_secret)
      {
        "X-GitHub-Event" => event_type,
        "X-Hub-Signature" => signature,
        "Content-Type" => "application/json",
      }
    end

    describe "with an invalid webhook signature" do
      let(:webhook_secret) { "invalid secret" }

      it "fails" do
        expect(HandleWebhook::IssueComment).not_to receive(:new)
        post "/github_webhooks/discard", params: request_body, headers: headers
        expect(response).to be_forbidden
      end
    end

    describe "with a valid webhook signature" do
      it "logs and responds with a success code" do
        post "/github_webhooks/discard", params: request_body, headers: headers
        expect(response).to be_successful
        expect(response.body).to be_empty
      end
    end
  end
end
