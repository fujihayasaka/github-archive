# frozen_string_literal: true

require "rails_helper"

RSpec.describe PauseRepoJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new(repo_id: repo.id, event_source: "test") }

  let(:repo) { create(:repo) }
  let(:repo_url) do
    github_url + "repositories/#{repo.github_id}/"
  end
  let(:twirp_settings_client) do
    instance_double(
      GitHub::Twirp::DependabotRepositorySettings,
      set_paused_flag_on_repository: MonolithTwirp::Dependabot::Settings::V1::SetPausedFlagOnRepositoryResponse.new(
        id: repo.github_id, success: true
      )
    )
  end
  let(:dummy_deactivater) do
    instance_double(DeactivateRepo, run: nil)
  end

  let(:twirp_error) do
    GitHub::Twirp::DependabotRepositorySettings::Error.new("internal - lp0 on fire")
  end

  before do
    allow(Dependabot::Application).to receive(:dependabot_repository_settings_client).and_return(twirp_settings_client)
  end

  it "updates the paused flag in dotcom and in the database", feature: :inactivity_pausing do
    expect(twirp_settings_client).to receive(:set_paused_flag_on_repository)

    expect { job.perform_now }.to change { repo.reload.paused? }.from(false).to(true)
  end

  it "clears next_enqueue_at for all update configs", feature: :inactivity_pausing do
    update_config = create(:update_config, repo: repo, next_enqueue_at: 1.day.from_now)

    expect { job.perform_now }.to change { update_config.reload.next_enqueue_at }.to(nil)
  end

  it "does not attempt to pause in dotcom if the repo is already paused", feature: :inactivity_pausing do
    repo.update(paused_at: 1.minute.ago)

    expect(twirp_settings_client).not_to receive(:set_paused_flag_on_repository)

    expect { job.perform_now }.not_to change { repo.reload.paused? }.from(true)
  end

  it "retries the job if setting the paused flag fails", feature: :inactivity_pausing do
    allow(twirp_settings_client).to receive(:set_paused_flag_on_repository).and_raise(twirp_error)

    expect { job.perform_now }.to enqueue_job(described_class)
  end

  it "does not pause the repo if the pause call to dotcom returns false", feature: :inactivity_pausing do
    allow(twirp_settings_client).to receive(:set_paused_flag_on_repository).and_return(
      MonolithTwirp::Dependabot::Settings::V1::SetPausedFlagOnRepositoryResponse.new(id: repo.github_id, success: false)
    )

    expect { job.perform_now }.not_to change { repo.reload.paused? }
    expect(repo.reload.will_pause_at).to be_nil
  end

  it "deactivates the repo if the repo was not found", feature: :inactivity_pausing do
    allow(twirp_settings_client).to receive(:set_paused_flag_on_repository).and_raise(
      GitHub::Twirp::DependabotRepositorySettings::NotFound.new("not found")
    )
    allow(DeactivateRepo).
      to receive(:new).
      and_return(dummy_deactivater)
    expect(dummy_deactivater).to receive(:run)

    expect { job.perform_now }.not_to change { repo.reload.paused? }
    expect(repo.reload.will_pause_at).to be_nil
  end

  context "audit logging", feature: :inactivity_pausing do
    it "publishes an audit log hydro message" do
      job.perform_now
      message = Dependabot.hydro_sink.messages.last
      message_data = decode_hydro_message(message.data)
      expect(message_data[:action][:value]).to eq("dependabot_updates.repository_paused")
      expect(message.schema).to eq("hydro.schemas.audit_log.v2.AuditEntry")
    end
  end

  context "updating pull requests is blocked if relaying the flag to dotcom fails" do
    before do
      allow(twirp_settings_client).to receive(:set_paused_flag_on_repository).and_raise(twirp_error)
    end

    it "does not update the pull request" do
      expect { job.perform_now }.not_to change { repo.reload.paused? }.from(false)
    end
  end
end
