# frozen_string_literal: true

require "rails_helper"

RSpec.describe Routes::GitHubWebhooks::Discard do
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

  context "with a webhook action" do
    let(:webhook_action) { "pull_request" }
    let(:webhook_body) { json_fixture("github_webhooks/pull_request_opened") }

    it { is_expected.to respond_with_status(204) }

    it "logs and discards the webhook" do
      expect(Rails.logger).to receive(:info).with("Log and discard webhook action: #{webhook_action}")
      instance.call
    end
  end
end
