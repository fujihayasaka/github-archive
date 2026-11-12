# frozen_string_literal: true

require "rails_helper"

require_relative "../../../../lib/dependabot/transitions/20210610135251_resync_default_schedules.rb"

RSpec.describe "ResyncDefaultSchedules" do
  let(:transition) do
    Dependabot::Transitions::ResyncDefaultSchedules.new(dry_run: false, limit: nil, offset: 0, rollback: rollback)
  end
  let(:dry_run_transition) do
    Dependabot::Transitions::ResyncDefaultSchedules.new(limit: nil, offset: 0, rollback: rollback)
  end
  let(:rollback) { false }
  let(:old_default_time) { Dependabot::Transitions::ResyncDefaultSchedules::OLD_DEFAULT_UPDATE_SCHEDULE_TIME_OF_DAY }
  let(:updatable_config) { FactoryBot.create(:update_config, :active, update_schedule_time_of_day: old_default_time) }
  let(:non_default_schedule) { FactoryBot.create(:update_config, :active, update_schedule_time_of_day: "12:34") }

  before do
    allow(Stafftools::ResyncRepoJob).to receive(:perform_later)

    # inactive or non-scheduled (security updates) configs will be ignored:
    FactoryBot.create(:update_config, :deleted)
    FactoryBot.create(:update_config, update_schedule: "never")

    # multiple configurations in a single repository should only trigger one resync:
    FactoryBot.create(:update_config, :active,
                      repo: updatable_config.repo, directory: "/module",
                      update_schedule_time_of_day: old_default_time)
  end

  def expect_scheduled_resync(*configs)
    transition.perform

    expect(Stafftools::ResyncRepoJob).
      to have_received(:perform_later).
      exactly(configs.count).times

    configs.each do |config|
      expect(Stafftools::ResyncRepoJob).to have_received(:perform_later).with(
        account: config.account,
        github_id: config.repo.github_id
      ).once
    end
  end

  context "write" do
    it "schedules sync of repo" do
      expect_scheduled_resync(updatable_config)
    end

    context "rollback" do
      let(:rollback) { true }

      it "schedules jobs" do
        expect_scheduled_resync(updatable_config, non_default_schedule)
      end
    end
  end

  context "dry run" do
    it "does nothing on a dry run" do
      dry_run_transition.perform

      expect(Stafftools::ResyncRepoJob).not_to have_received(:perform_later)
    end
  end
end
