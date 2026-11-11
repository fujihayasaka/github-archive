# frozen_string_literal: true

require "rails_helper"
require_relative "../../../../lib/dependabot/transitions/20260114210000_backfill_security_updates_incident.rb"

RSpec.describe Dependabot::Transitions::BackfillSecurityUpdatesIncident do
  let(:transition) do
    described_class.new(dry_run: false, batch_size: batch_size, backfill_limit: backfill_limit)
  end

  let(:dry_run_transition) do
    described_class.new(batch_size: batch_size, backfill_limit: backfill_limit)
  end

  let(:batch_size) { 2 }
  let(:backfill_limit) { 1000 }

  let(:dependabot_account) do
    Account.find_by(github_login: "dependabot") || build(:account, :active, :dependabot)
  end

  # Create repos with github_ids that are in the affected repo IDs
  let(:affected_repo_ids) { described_class.affected_repo_ids.first(5) }

  let!(:affected_repos) do
    affected_repo_ids.map do |github_id|
      create(:repo, :active,
             account: dependabot_account,
             github_id: github_id,
             security_updates_enabled: nil)
    end
  end

  let!(:unaffected_repos) do
    create_list(:repo, 3, :active,
                account: dependabot_account,
                security_updates_enabled: nil)
  end

  let(:dependabot_repository_settings_client) do
    instance_double(
      GitHub::Twirp::DependabotRepositorySettings,
      get_repository_settings: double(automated_security_updates_enabled: true),
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

  describe "#perform" do
    context "when writing" do
      it "updates security_updates_enabled for affected repos only" do
        expect(affected_repos.pluck(:security_updates_enabled)).to all(be_nil)
        expect(unaffected_repos.pluck(:security_updates_enabled)).to all(be_nil)

        transition.perform

        affected_repos.map(&:reload)
        unaffected_repos.map(&:reload)

        expect(affected_repos.pluck(:security_updates_enabled)).to all(be(true))
        expect(unaffected_repos.pluck(:security_updates_enabled)).to all(be_nil)

        expect(dependabot_repository_settings_client).
          to have_received(:get_repository_settings).exactly(5).times
      end

      context "when backfill_limit is reached" do
        let(:backfill_limit) { 3 }

        it "stops after reaching the limit" do
          transition.perform

          affected_repos.map(&:reload)

          updated_count = affected_repos.count { |r| r.security_updates_enabled == true }
          expect(updated_count).to eq(3)

          expect(dependabot_repository_settings_client).
            to have_received(:get_repository_settings).exactly(3).times
        end
      end

      context "when an error occurs" do
        before do
          call_count = 0
          allow(dependabot_repository_settings_client).to receive(:get_repository_settings) do
            call_count += 1
            raise StandardError, "API error" if call_count == 2

            double(automated_security_updates_enabled: true)
          end
        end

        it "continues processing other repos" do
          transition.perform

          affected_repos.map(&:reload)

          # 4 repos should be updated (1 failed)
          updated_count = affected_repos.count { |r| r.security_updates_enabled == true }
          expect(updated_count).to eq(4)
        end
      end
    end

    context "when dry run" do
      it "does not update any repos" do
        expect(affected_repos.pluck(:security_updates_enabled)).to all(be_nil)

        dry_run_transition.perform

        affected_repos.map(&:reload)

        expect(affected_repos.pluck(:security_updates_enabled)).to all(be_nil)
        expect(dependabot_repository_settings_client).not_to have_received(:get_repository_settings)
        expect(freno_throttler).not_to have_received(:throttle)
      end
    end
  end

  describe ".affected_repo_ids" do
    it "contains the expected number of repo IDs" do
      expect(described_class.affected_repo_ids.count).to eq(11_896)
    end

    it "contains only integers" do
      expect(described_class.affected_repo_ids).to all(be_a(Integer))
    end
  end
end
