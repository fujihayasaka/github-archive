# frozen_string_literal: true

require "rails_helper"

require_relative "../../../../lib/dependabot/transitions/20260316_resync_broken_cron_schedules.rb"

RSpec.describe "ResyncBrokenCronSchedules" do
  let(:cron_expression) { "0 5 * * 1" }

  let(:transition) do
    Dependabot::Transitions::ResyncBrokenCronSchedules.new(dry_run: false, backfill_limit: 100)
  end

  let(:dry_run_transition) do
    Dependabot::Transitions::ResyncBrokenCronSchedules.new(backfill_limit: 100)
  end

  # Creates an active cron config with a broken (nil) next_enqueue_at.
  def create_broken_cron_config(**overrides)
    config = create(:update_config, :active, :cron,
                    update_schedule_cron_expression: cron_expression,
                    **overrides)
    # The :active factory transition calls update_next_enqueue_at!, so we must
    # manually clear next_enqueue_at to simulate the broken state.
    config.update_column(:next_enqueue_at, nil)
    config
  end

  # Creates a rate-limited cron config with a broken (nil) next_enqueue_at.
  def create_broken_rate_limited_cron_config(**overrides)
    config = create(:update_config, :rate_limited, :cron,
                    update_schedule_cron_expression: cron_expression,
                    **overrides)
    # The :rate_limited factory transition also sets next_enqueue_at, so we
    # manually clear it to simulate the broken state.
    config.update_column(:next_enqueue_at, nil)
    config
  end

  before do
    allow(Stafftools::ResyncAccountJob).to receive(:perform_later)
  end

  context "write" do
    it "enqueues a resync job for each account with a broken cron config" do
      config = create_broken_cron_config
      account = config.repo.account

      transition.perform

      expect(Stafftools::ResyncAccountJob).to have_received(:perform_later).once.with(account: account)
    end

    it "enqueues a resync job for a broken rate_limited cron config" do
      config = create(:update_config, :rate_limited, :cron, update_schedule_cron_expression: cron_expression)
      config.update_column(:next_enqueue_at, nil)
      account = config.repo.account

      transition.perform

      expect(Stafftools::ResyncAccountJob).to have_received(:perform_later).once.with(account: account)
    end

    it "enqueues each account only once even with multiple broken configs" do
      config = create_broken_cron_config
      account = config.repo.account

      # Second config on the same account (different repo)
      create_broken_cron_config(repo: create(:repo, account: account))

      # Third config on the same repo, different directory
      create_broken_cron_config(repo: config.repo, directory: "/module")

      transition.perform

      expect(Stafftools::ResyncAccountJob).to have_received(:perform_later).once.with(account: account)
    end

    it "enqueues separate jobs for different accounts" do
      config1 = create_broken_cron_config
      config2 = create_broken_cron_config

      transition.perform

      expect(Stafftools::ResyncAccountJob).to have_received(:perform_later).twice
      expect(Stafftools::ResyncAccountJob).to have_received(:perform_later).with(account: config1.repo.account)
      expect(Stafftools::ResyncAccountJob).to have_received(:perform_later).with(account: config2.repo.account)
    end

    it "respects backfill_limit" do
      3.times { create_broken_cron_config }

      limited_transition = Dependabot::Transitions::ResyncBrokenCronSchedules.new(dry_run: false, backfill_limit: 2)
      limited_transition.perform

      expect(Stafftools::ResyncAccountJob).to have_received(:perform_later).exactly(2).times
    end

    it "enqueues a resync job for a broken rate-limited cron config" do
      config = create_broken_rate_limited_cron_config
      account = config.repo.account

      transition.perform

      expect(Stafftools::ResyncAccountJob).to have_received(:perform_later).once.with(account: account)
    end

    it "does not enqueue for configs where next_enqueue_at is already set" do
      # Config with next_enqueue_at set is not broken — should be excluded
      create(:update_config, :active, :cron, update_schedule_cron_expression: cron_expression)

      transition.perform

      expect(Stafftools::ResyncAccountJob).not_to have_received(:perform_later)
    end

    it "does not enqueue for paused repos" do
      paused_repo = create(:repo, :currently_paused)
      create_broken_cron_config(repo: paused_repo)

      transition.perform

      expect(Stafftools::ResyncAccountJob).not_to have_received(:perform_later)
    end

    it "does not enqueue for non-cron schedules" do
      daily_config = create(:update_config, :active)
      daily_config.update_column(:next_enqueue_at, nil)

      transition.perform

      expect(Stafftools::ResyncAccountJob).not_to have_received(:perform_later)
    end

    it "does not enqueue for deleted configs" do
      config = create(:update_config, :deleted, :cron,
                      update_schedule_cron_expression: cron_expression)
      config.update_column(:next_enqueue_at, nil)

      transition.perform

      expect(Stafftools::ResyncAccountJob).not_to have_received(:perform_later)
    end

    it "does not enqueue for configs with a nil cron expression" do
      # :cron trait sets update_schedule to 'cron' but cron expression stays nil
      config = create(:update_config, :active, :cron, update_schedule_cron_expression: nil)
      config.update_column(:next_enqueue_at, nil)

      transition.perform

      expect(Stafftools::ResyncAccountJob).not_to have_received(:perform_later)
    end
  end

  context "dry run" do
    it "does not enqueue any jobs" do
      create_broken_cron_config

      dry_run_transition.perform

      expect(Stafftools::ResyncAccountJob).not_to have_received(:perform_later)
    end
  end
end
