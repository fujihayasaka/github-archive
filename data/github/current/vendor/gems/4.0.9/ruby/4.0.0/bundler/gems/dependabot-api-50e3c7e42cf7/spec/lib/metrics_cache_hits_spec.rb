# frozen_string_literal: true

require "rails_helper"
require "metrics_cache_hits"

RSpec.describe "Cache hit metrics", type: :integration do
  before do
    Rails.cache.clear
  end

  it "records cache hits that are tracked" do
    allow(MetricsClient).to receive(:increment)
    allow(Dependabot::Logger).to receive(:info)

    Rails.cache.fetch("update_job_logs/s3/1") { true }
    Rails.cache.fetch("update_job_logs/s3/1") { true }

    expect(MetricsClient).to have_received(:increment).
      with("cache.update_job_logs_s3", tags: { hit: false }).
      with("cache.update_job_logs_s3", tags: { hit: true })

    # The logged key includes the cache namespace prefix
    cache_namespace = Rails.application.config.cache_store[1][:namespace]
    namespaced_key = "#{cache_namespace}:update_job_logs/s3/1"

    expect(Dependabot::Logger).to have_received(:info).
      with(msg: "cache read", name: :update_job_logs_s3, hit: false, key: namespaced_key).
      with(msg: "cache read", name: :update_job_logs_s3, hit: true, key: namespaced_key)
  end

  it "does not record untracked cache hits" do
    allow(MetricsClient).to receive(:increment)
    allow(Dependabot::Logger).to receive(:info)

    Rails.cache.fetch("some/untracked/key") { true }
    Rails.cache.fetch("some/untracked/key") { true }

    expect(MetricsClient).not_to have_received(:increment)
    expect(Dependabot::Logger).not_to have_received(:info)
  end
end
