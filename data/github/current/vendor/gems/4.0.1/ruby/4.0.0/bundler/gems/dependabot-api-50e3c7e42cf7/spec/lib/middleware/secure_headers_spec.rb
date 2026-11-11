# frozen_string_literal: true

require "rails_helper"
require "middleware/secure_headers"

RSpec.describe Middleware::SecureHeaders, type: :request do
  include ProximaHelpers

  let(:header) do
    { "Content-Type" => "application/json", "Authorization" => base64_token }
  end

  let(:token) { RbNaCl::Random.random_bytes(RbNaCl::SecretBox.key_bytes) }
  let(:base64_token) { Base64.strict_encode64(token) }
  let(:update_config) { FactoryBot.create(:update_config) }

  let(:update_job) do
    FactoryBot.create(
      :update_job, :processing,
      id: 1001,
      update_config: update_config,
      hashed_token: Base64.strict_encode64(RbNaCl::Hash.sha256(token)),
    )
  end
  let(:previous_update_job) do
    FactoryBot.create(:update_job, update_config: update_config)
  end

  before do
    FactoryBot.create(:pull_request, update_job: previous_update_job)
    FactoryBot.create(:ignore_condition, update_config: update_config)
  end

  it "sets hsts header on requests" do
    stub_proxima_repo_request(repo_id: update_job.repo.github_id, fixture: "proxima_repo")

    get "/update_jobs/#{update_job.id}/details", headers: header

    expect(response.headers["Strict-Transport-Security"]).to eq(
      "max-age=31557600; includeSubDomains; preload"
    )
  end
end
