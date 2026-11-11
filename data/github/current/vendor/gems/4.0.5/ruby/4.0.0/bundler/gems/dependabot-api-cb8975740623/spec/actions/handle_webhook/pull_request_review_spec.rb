# frozen_string_literal: true

require "rails_helper"

RSpec.describe HandleWebhook::PullRequestReview do
  include ActiveJob::TestHelper

  subject(:action) { described_class.new(webhook_body: webhook_body, headers: headers) }

  let(:audit_log) { instance_double(Activity::PullRequestLogger, record_event: nil) }
  let(:webhook_body) do
    hash = json_fixture("github_webhooks/pull_request_review")
    hash.deep_symbolize_keys
  end
  let(:headers) { nil }

  before do
    allow(Activity::PullRequestLogger).to receive(:new).and_return(audit_log)
  end

  context "for a non-dependabot issue" do
    it "no-ops" do
      expect(Rails.logger).not_to receive(:info)
      action.run
    end
  end

  context "for a dependabot pull request" do
    before do
      FactoryBot.create(:pull_request, :bump_test, github_number: 122)
    end

    let(:dummy_issue_comment_handler) do
      instance_double(HandleWebhook::IssueComment, run: nil)
    end

    shared_examples "delegates to HandleWebhook::IssueComment" do
      it "delegates to HandleWebhook::IssueComment" do
        expect(HandleWebhook::IssueComment).
          to receive(:new).with(webhook_body: webhook_body, headers: headers).
          and_return(dummy_issue_comment_handler)
        expect(dummy_issue_comment_handler).to receive(:run)

        perform_enqueued_jobs do
          action.run
        end
      end
    end

    describe "given a 'random' webhook" do
      before { webhook_body[:action] = "random" }

      include_examples "delegates to HandleWebhook::IssueComment"
    end

    describe "given a 'submitted' webhook" do
      before { webhook_body[:action] = "submitted" }

      context "that approves the PR" do
        before { webhook_body[:review][:state] = "approved" }

        include_examples "delegates to HandleWebhook::IssueComment"

        it "logs the PR activity as approved" do
          expect(audit_log).to receive(:record_event).with("approved", tags: { merge_requested: false })
          action.run
        end
      end
    end
  end
end
