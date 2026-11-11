# frozen_string_literal: true

require "rails_helper"

RSpec.describe AfterUnpauseRepoJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new(repo_id: repo.id) }

  let(:repo) { create(:repo, :currently_paused) }

  let(:twirp_settings_client) do
    instance_double(
      GitHub::Twirp::DependabotRepositorySettings,
      remove_paused_flag_on_repository: {}
    )
  end

  let(:twirp_error) do
    GitHub::Twirp::DependabotRepositorySettings::Error.new("internal - lp0 on fire")
  end

  before do
    allow(MetricsClient).to receive(:increment)
    allow(Dependabot::Application).to receive(:dependabot_repository_settings_client).and_return(twirp_settings_client)
  end

  it "updates the paused flag in dotcom", feature: :inactivity_pausing do
    expect(twirp_settings_client).to receive(:remove_paused_flag_on_repository)

    described_class.perform_now(repo_id: repo.id)
  end

  it "retries the job if removing the paused flag fails", :cloud do
    allow(twirp_settings_client).to receive(:remove_paused_flag_on_repository).and_raise(twirp_error)

    expect { described_class.perform_now(repo_id: repo.id) }.to enqueue_job(described_class)
  end

  context "audit logging", feature: :inactivity_pausing do
    it "publishes an audit log hydro message" do
      described_class.perform_now(repo_id: repo.id)
      message = Dependabot.hydro_sink.messages.last
      message_data = decode_hydro_message(message.data)
      expect(message_data[:action][:value]).to eq("dependabot_updates.repository_unpaused")
      expect(message.schema).to eq("hydro.schemas.audit_log.v2.AuditEntry")
    end
  end
end
