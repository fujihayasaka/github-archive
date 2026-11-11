# frozen_string_literal: true

require "rails_helper"

RSpec.describe Middlewares::CheckGitHubWebhookSignature do
  subject(:instance) { described_class.new(context, null_middleware) }

  let(:context) do
    {
      request: instance_double(
        ActionDispatch::Request,
        headers: headers,
        body: StringIO.new(request_body),
      ),
    }
  end
  let(:headers) do
    signature = GitHubHelpers.webhook_signature(request_body, webhook_secret)
    { "X-Hub-Signature" => signature }
  end
  let(:request_body) { "{}" }
  let(:webhook_secret) { Prius.get(:github_integration_webhook_secret) }

  context "with valid signature" do
    it { is_expected.to call_next_middleware }
  end

  context "with an invalid signature" do
    let(:webhook_secret) { "invalid secret" }

    it { is_expected.to respond_with_status(403) }
  end

  context "with no webhook signature" do
    let(:headers) { {} }

    it { is_expected.to respond_with_status(403) }
  end
end
