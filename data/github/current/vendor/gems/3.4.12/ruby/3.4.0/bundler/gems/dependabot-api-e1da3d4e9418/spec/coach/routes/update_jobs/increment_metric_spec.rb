# frozen_string_literal: true

require "rails_helper"

RSpec.describe Routes::UpdateJobs::IncrementMetric do
  subject(:instance) { described_class.new(context) }

  let(:context) { { request: request, update_job: update_job } }
  let(:request) { instance_double(ActionDispatch::Request, params: params) }
  let(:update_job) { FactoryBot.create(:update_job, :processing) }

  let(:expected_runner_type) { "actions" }

  context "for an allowed metric" do
    let(:params)  do
      ActiveSupport::HashWithIndifferentAccess.new(
        data: { metric: "updater.started", "tags" => { "operation" => "update_all_versions" } },
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

  context "for an allowed metric with a disallowed tag" do
    let(:params)  do
      ActiveSupport::HashWithIndifferentAccess.new(
        data: { metric: "updater.started",
                "tags" => { "operation" => "update_all_versions", "sekret" => "swordfish" }, },
      )
    end

    it "is a successful request" do
      expect(instance).to respond_with_status(204)
    end

    it "increments the relayed metric without the disallowed tag" do
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

  context "for an allowed metric with an over-long tag value" do
    let(:params)  do
      ActiveSupport::HashWithIndifferentAccess.new(
        data: {
          metric: "updater.started",
          "tags" => {
            "operation" => "this_is_longer_than_is_reasonable",
          },
        },
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

  context "for a disallowed metric" do
    let(:params) do
      ActiveSupport::HashWithIndifferentAccess.new(
        data: { metric: "updater.on-fire", "tags" => { "operation" => "update_all_versions" } },
      )
    end

    it "is a successful request" do
      expect(instance).to respond_with_status(204)
    end

    it "does not update the metric" do
      expect(MetricsClient).not_to receive(:count).with("updater.on-fire", tags: anything)

      instance.call
    end
  end
end
