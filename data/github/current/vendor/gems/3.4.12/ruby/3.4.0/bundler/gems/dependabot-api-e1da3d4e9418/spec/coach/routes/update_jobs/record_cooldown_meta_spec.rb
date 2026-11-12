# frozen_string_literal: true

require "rails_helper"

RSpec.describe Routes::UpdateJobs::RecordCooldownMeta do
  subject(:instance) { described_class.new(context) }

  let(:context) { { request: request, update_job: update_job } }
  let(:request) { instance_double(ActionDispatch::Request, params: params) }
  let(:update_job) { FactoryBot.create(:update_job, :processing) } # rubocop:disable FactoryBot/SyntaxMethods
  let(:ecosystem_name) { "npm_and_yarn" }
  let(:cooldown_config) do
    {
      default_days: "90",
      semver_major_days: "7",
      semver_minor_days: "7",
      semver_patch_days: "7",
    }
  end

  let(:params) do
    ActiveSupport::HashWithIndifferentAccess.new(
      data: [
        {
          cooldown: {
            ecosystem_name: ecosystem_name,
            config: cooldown_config,
          },
        },
      ]
    )
  end

  let(:tags) do
    {
      "cooldown.ecosystem_name" => "npm_and_yarn",
      "config.default_days" => "90",
      "config.semver_major_days" => "7",
      "config.semver_minor_days" => "7",
      "config.semver_patch_days" => "7",
    }
  end

  it "makes a call to send cooldown metadata to datadog" do
    expect(MetricsClient).to receive(:count).with(
      "update_job.cooldown_meta", 1, tags: hash_including(tags)
    ).once

    instance.call
  end
end
