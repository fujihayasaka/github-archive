# frozen_string_literal: true

require "rails_helper"

RSpec.describe Routes::UpdateJobs::RecordMetrics do
  subject(:instance) { described_class.new(context) }

  let(:context) { { request: request, update_job: update_job } }
  let(:request) { instance_double(ActionDispatch::Request, params: params) }
  let(:update_job) { FactoryBot.create(:update_job, :processing) }

  let(:expected_runner_type) { "actions" }

  context "for an allowed increment metric" do
    let(:params) do
      ActiveSupport::HashWithIndifferentAccess.new(
        data: [
          { metric: "updater.started", type: "increment", value: 1, tags: { operation: "update_all_versions" } },
        ],
      )
    end

    it "is a successful request" do
      expect(instance).to respond_with_status(204)
    end

    it "increments the relayed metric" do
      expect(MetricsClient).to receive(:count).with(
        "updater.started", 1,
        tags: hash_including({
                               operation: "update_all_versions",
                               runner_type: expected_runner_type,
                             })
      ).once

      instance.call
    end
  end

  context "for an allowed distribution metric" do
    let(:params) do
      ActiveSupport::HashWithIndifferentAccess.new(
        data: [
          { metric: "dependabot.job_proxy.http_response_duration_ms", type: "distribution", values: [12.34],
            tags: { package_manager: "foo", grouped_update: "false", request_host: "example.com" }, },
        ],
      )
    end

    it "is a successful request" do
      expect(instance).to respond_with_status(204)
    end

    it "records the distribution metric with the given value" do
      expect(MetricsClient).to receive(:distribution).with(
        "dependabot.job_proxy.http_response_duration_ms",
        12.34,
        tags: hash_including({
                               package_manager: "foo",
                               grouped_update: "false",
                               request_host: "example.com",
                               runner_type: expected_runner_type,
                             })
      ).once

      instance.call
    end
  end

  context "for an allowed metric with an over-long tag value" do
    let(:params) do
      ActiveSupport::HashWithIndifferentAccess.new(
        data: [
          { metric: "updater.started", type: "increment", value: 1,
            tags: { operation: "this_is_longer_than_is_reasonable" }, },
        ],
      )
    end

    it "is a successful request" do
      expect(instance).to respond_with_status(204)
    end

    it "increments the relayed metric with a truncated value for the tag" do
      expect(MetricsClient).to receive(:count).with(
        "updater.started", 1,
        tags: hash_including({
                               operation: "this_is_longer_than_is_reason...",
                               runner_type: expected_runner_type,
                             })
      ).once

      instance.call
    end
  end

  context "for an allowed metric with an package-manager tag value" do
    let(:params) do
      ActiveSupport::HashWithIndifferentAccess.new(
        data: [
          { metric: "dependabot.action.ghcr_image_pull", type: "increment", value: 1,
            tags: { package_manager: "composer", org: "dependabot" }, },
        ],
      )
    end

    it "is a successful request" do
      expect(instance).to respond_with_status(204)
    end

    it "increments the relayed metric with a truncated value for the tag" do
      expect(MetricsClient).to receive(:count).with(
        "dependabot.action.ghcr_image_pull", 1,
        tags: hash_including({
                               package_manager: "composer",
                               org: "dependabot",
                             })
      ).once

      instance.call
    end
  end

  # rubocop:disable RSpec/ExampleLength
  context "for batch processing of multiple metrics" do
    let(:params) do
      ActiveSupport::HashWithIndifferentAccess.new(
        data: [
          { metric: "updater.started", type: "increment", value: 1, tags: { operation: "update_all_versions" } },
          { metric: "dependabot.job_proxy.http_request_count", type: "increment", value: 10,
            tags: { package_manager: "foo", grouped_update: "false", request_host: "example.com" }, },
          { metric: "dependabot.job_proxy.http_response_duration_ms", type: "distribution", values: [12.34, 15.67],
            tags: { package_manager: "foo", grouped_update: "false", request_host: "example.com" }, },
          { metric: "dependabot.job_proxy.http_response_duration_ms", type: "distribution", values: [5.6, 7.8],
            tags: { package_manager: "foo", grouped_update: "false", request_host: "example.com" }, },
        ],
      )
    end

    it "is a successful request" do
      expect(instance).to respond_with_status(204)
    end

    it "processes all metrics in the batch correctly" do
      # Expectation for the increment metric
      expect(MetricsClient).to receive(:count).with(
        "updater.started", 1,
        tags: hash_including({ operation: "update_all_versions", runner_type: expected_runner_type })
      ).once

      # Expectation for the increment metric
      expect(MetricsClient).to receive(:count).with(
        "dependabot.job_proxy.http_request_count", 10,
        tags: hash_including({ package_manager: "foo", grouped_update: "false", request_host: "example.com" })
      ).once

      # Expectations for the first distribution metric
      expect(MetricsClient).to receive(:distribution).with(
        "dependabot.job_proxy.http_response_duration_ms",
        12.34,
        tags: hash_including({ package_manager: "foo", grouped_update: "false", request_host: "example.com" })
      ).once

      expect(MetricsClient).to receive(:distribution).with(
        "dependabot.job_proxy.http_response_duration_ms",
        15.67,
        tags: hash_including({ package_manager: "foo", grouped_update: "false", request_host: "example.com" })
      ).once

      # Expectations for the second distribution metric
      expect(MetricsClient).to receive(:distribution).with(
        "dependabot.job_proxy.http_response_duration_ms",
        5.6,
        tags: hash_including({ package_manager: "foo", grouped_update: "false", request_host: "example.com" })
      ).once

      expect(MetricsClient).to receive(:distribution).with(
        "dependabot.job_proxy.http_response_duration_ms",
        7.8,
        tags: hash_including({ package_manager: "foo", grouped_update: "false", request_host: "example.com" })
      ).once

      instance.call
    end
  end
  # rubocop:enable RSpec/ExampleLength

  context "for a disallowed metric" do
    let(:params) do
      ActiveSupport::HashWithIndifferentAccess.new(
        data: [
          { metric: "updater.on-fire", type: "increment", tags: { operation: "update_all_versions" } },
        ],
      )
    end

    it "is a bad request" do
      expect(instance).to respond_with_status(400)
    end

    it "does not update the metric" do
      expect(MetricsClient).not_to receive(:count).with("updater.on-fire", tags: anything)

      instance.call
    end
  end

  context "for a disallowed metric tag" do
    let(:params) do
      ActiveSupport::HashWithIndifferentAccess.new(
        data: [
          { metric: "updater.on-fire", type: "increment", tags: { operation: 1234 } },
        ],
      )
    end

    it "is a bad request" do
      expect(instance).to respond_with_status(400)
    end

    it "does not update the metric" do
      expect(MetricsClient).not_to receive(:count).with("updater.on-fire", tags: anything)

      instance.call
    end
  end

  context "for a disallowed metric type" do
    let(:params) do
      ActiveSupport::HashWithIndifferentAccess.new(
        data: [
          { metric: "updater.on-fire", type: "foobar", tags: { operation: "update_all_versions" } },
        ],
      )
    end

    it "is a bad request" do
      expect(instance).to respond_with_status(400)
    end

    it "does not update the metric" do
      expect(MetricsClient).not_to receive(:count).with("updater.on-fire", tags: anything)

      instance.call
    end
  end
end
