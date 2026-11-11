# frozen_string_literal: true

require "rails_helper"
require_relative "../../../../lib/dependabot/transitions/20230201021645_backfill_repo_security_updates_enabled.rb"

RSpec.describe Dependabot::Transitions::BackfillRepoSecurityUpdatesEnabled do
  let(:transition) do
    described_class.new(dry_run: false, batch_size: batch_size, backfill_limit: backfill_limit)
  end

  let(:dry_run_transition) do
    described_class.new(batch_size: batch_size, backfill_limit: backfill_limit)
  end

  let(:batch_size) { 2 }

  let(:backfill_limit) { 1000 }

  let(:qualifying_time) do
    described_class.const_get(:ROLLOUT_PHASE2_END_AT).advance(days: -1)
  end

  let(:dependabot_account) do
    Account.find_by(github_login: "dependabot") || FactoryBot.build(:account, :active, :dependabot)
  end

  let!(:other_repos) do
    FactoryBot.create_list(:repo, 2, :security_updates_only, :manual_security_updates,
                           paused_at: nil,
                           will_pause_at: nil)
  end

  let!(:paused_repos) do
    FactoryBot.create_list(:repo, 3, :security_updates_only, :manual_security_updates,
                           paused_at: qualifying_time,
                           will_pause_at: nil)
  end

  let!(:active_target_repos) do
    FactoryBot.create_list(:repo, 5, :security_updates_only,
                           account: dependabot_account,
                           security_updates_enabled: nil,
                           paused_at: nil,
                           will_pause_at: qualifying_time)
  end

  let!(:inactive_target_repos) do
    FactoryBot.create_list(:repo, 5, :inactive,
                           security_updates_enabled: nil,
                           paused_at: nil,
                           will_pause_at: qualifying_time)
  end

  let!(:future_target_repos) do
    FactoryBot.create_list(:repo, 2, :will_pause_later, :security_updates_only,
                           security_updates_enabled: nil,
                           paused_at: nil)
  end

  let(:dependabot_repository_settings_client) do
    instance_double(
      GitHub::Twirp::DependabotRepositorySettings,
      get_repository_settings: OpenStruct.new(automated_security_updates_enabled: true),
    )
  end

  let(:freno_throttler) do
    instance_double(Freno::Throttler)
  end

  before do
    allow(Dependabot::Application).
      to receive(:dependabot_repository_settings_client).
      and_return(dependabot_repository_settings_client)

    allow(freno_throttler).to receive(:throttle).and_yield
    allow(Dependabot).to receive(:freno_throttler).and_return(freno_throttler)
  end

  context "write" do
    # rubocop:disable RSpec/ExampleLength
    it "performs the transition" do
      expect(active_target_repos.pluck(:security_updates_enabled)).to all(be_nil)
      expect(inactive_target_repos.pluck(:security_updates_enabled)).to all(be_nil)
      expect(future_target_repos.pluck(:security_updates_enabled)).to all(be_nil)
      expect((other_repos + paused_repos).pluck(:security_updates_enabled)).to all(eq(false))

      transition.perform

      (
        active_target_repos +
        inactive_target_repos +
        future_target_repos +
        paused_repos +
        other_repos
      ).map(&:reload)

      expect(active_target_repos.pluck(:security_updates_enabled)).to all(eq(true))
      expect(inactive_target_repos.pluck(:security_updates_enabled)).to all(be_nil)
      expect(future_target_repos.pluck(:security_updates_enabled)).to all(be_nil)
      expect((paused_repos + other_repos).pluck(:security_updates_enabled)).to all(eq(false))

      expect(freno_throttler).to have_received(:throttle).exactly(3).times
      expect(dependabot_repository_settings_client).
        to have_received(:get_repository_settings).exactly(5).times
    end
    # rubocop:enable RSpec/ExampleLength

    context "when backfill_limit is given" do
      let(:batch_size) { 2 }
      let(:backfill_limit) { 3 }

      it "honors the backfill_limit" do
        expect(active_target_repos.pluck(:security_updates_enabled)).to eq([nil, nil, nil, nil, nil])

        transition.perform

        active_target_repos.map(&:reload)
        expect(active_target_repos.pluck(:security_updates_enabled)).to eq([true, true, true, nil, nil])

        expect(freno_throttler).to have_received(:throttle).exactly(2).times
        expect(dependabot_repository_settings_client).
          to have_received(:get_repository_settings).exactly(3).times
      end
    end

    context "when backfill_limit < batch_size" do
      let(:batch_size) { 100 }
      let(:backfill_limit) { 3 }

      it "honors the backfill_limit" do
        expect(active_target_repos.pluck(:security_updates_enabled)).to eq([nil, nil, nil, nil, nil])

        transition.perform

        active_target_repos.map(&:reload)
        expect(active_target_repos.pluck(:security_updates_enabled)).to eq([true, true, true, nil, nil])

        expect(freno_throttler).to have_received(:throttle).once
        expect(dependabot_repository_settings_client).
          to have_received(:get_repository_settings).exactly(3).times
      end
    end
  end

  context "dry run" do
    # rubocop:disable RSpec/ExampleLength
    it "does nothing on a dry run" do
      expect(active_target_repos.pluck(:security_updates_enabled)).to all(be_nil)
      expect(inactive_target_repos.pluck(:security_updates_enabled)).to all(be_nil)
      expect(future_target_repos.pluck(:security_updates_enabled)).to all(be_nil)
      expect((other_repos + paused_repos).pluck(:security_updates_enabled)).to all(eq(false))

      dry_run_transition.perform

      (
        active_target_repos +
        inactive_target_repos +
        future_target_repos +
        paused_repos +
        other_repos
      ).map(&:reload)

      expect(active_target_repos.pluck(:security_updates_enabled)).to all(be_nil)
      expect(inactive_target_repos.pluck(:security_updates_enabled)).to all(be_nil)
      expect(future_target_repos.pluck(:security_updates_enabled)).to all(be_nil)
      expect((other_repos + paused_repos).pluck(:security_updates_enabled)).to all(eq(false))

      expect(freno_throttler).not_to have_received(:throttle)
      expect(dependabot_repository_settings_client).not_to have_received(:get_repository_settings)
    end
    # rubocop:enable RSpec/ExampleLength
  end
end
