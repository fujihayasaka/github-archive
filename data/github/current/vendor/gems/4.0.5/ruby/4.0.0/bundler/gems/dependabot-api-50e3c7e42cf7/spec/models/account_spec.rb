# frozen_string_literal: true

require "rails_helper"

RSpec.describe Account, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  subject(:account) { FactoryBot.build_stubbed(:account) }

  it { is_expected.to be_valid }

  context "when in the Proxima environment", proxima: true do
    it "requires a tenant" do
      account.tenant = nil
      expect(account).not_to be_valid
    end

    it "is valid with a tenant id" do
      account.tenant = FactoryBot.build(:tenant)
      expect(account).to be_valid
    end
  end

  describe "#tenant" do
    it "returns a NullTenant outside of Proxima", proxima: false do
      expect(account.tenant).to be_a(NullTenant)
    end

    it "returns a Tenant in Proxima", :proxima do
      expect(account.tenant).to be_a(Tenant)
    end
  end

  describe "#event_source" do
    it "defaults to unknown" do
      expect(account.event_source).to eql("unknown")
    end

    it "may be webhook" do
      account.event_source = "webhook"
      expect(account.event_source).to eql("webhook")
    end

    it "may be hydro" do
      account.event_source = "hydro"
      expect(account.event_source).to eql("hydro")
    end

    it "may not be random" do
      expect do
        account.event_source = "random"
      end.to raise_error(ArgumentError)
    end

    it "is instrumented on creation" do
      expect(MetricsClient).to receive(:increment).
        with("account.created",
             tags: { event_source: "webhook" }).
        once

      account = FactoryBot.create(:account, event_source: "webhook")

      # We don't see a second call on update
      account.touch
    end
  end

  describe "#current_intallation_id" do
    subject { account.current_installation_id }

    context "when inactive" do
      let(:account) { FactoryBot.build_stubbed(:account, :inactive) }

      it { is_expected.to be_nil }
    end

    context "when active" do
      let(:account) do
        FactoryBot.create(:account, :active, installation_id: 101)
      end

      it { is_expected.to eq(101) }
    end
  end

  describe "#user?" do
    subject { account.user? }

    context "when a user account" do
      let(:account) { FactoryBot.build_stubbed(:account, :user) }

      it { is_expected.to eq(true) }
    end

    context "when an org account" do
      let(:account) { FactoryBot.build_stubbed(:account, :org) }

      it { is_expected.to eq(false) }
    end
  end

  describe "#org?" do
    subject { account.org? }

    context "when an org account" do
      let(:account) { FactoryBot.build_stubbed(:account, :org) }

      it { is_expected.to eq(true) }
    end

    context "when a user account" do
      let(:account) { FactoryBot.build_stubbed(:account, :user) }

      it { is_expected.to eq(false) }
    end
  end

  describe "#repository_accesses" do
    it "defaults to empty" do
      expect(account.repository_accesses).to be_empty
    end

    it "can be non-empty" do
      access = RepositoryAccess.new(account: account, github_id: 7)
      access.save!
      expect(account.repository_accesses).to contain_exactly(access)
    end
  end

  describe "Flipper Actor" do
    it "can be tested for feature flags" do
      expect(account.feature_enabled?(:foo)).to be false

      Dependabot.flipper[:foo].enable

      expect(account.feature_enabled?(:foo)).to be true
    end

    it "can have features enabled" do
      expect(account.feature_enabled?(:foo)).to be false

      account.enable_feature(:foo)

      expect(account.feature_enabled?(:foo)).to be true
    end

    it "can have features disabled" do
      account.enable_feature(:foo)

      expect(account.feature_enabled?(:foo)).to be true

      account.disable_feature(:foo)

      expect(account.feature_enabled?(:foo)).to be false
    end
  end

  describe "#using_global_app?" do
    subject { account.using_global_app? }

    context "default" do
      it { is_expected.to be false }
    end

    context "when inactive" do
      let(:account) { FactoryBot.build_stubbed(:account, :inactive) }

      it { is_expected.to be false }
    end

    context "when active with installation" do
      let(:account) do
        FactoryBot.create(:account, :active, installation_id: 101)
      end

      it { is_expected.to be false }
    end

    context "when active with global app" do
      let(:account) do
        FactoryBot.create(:account, :active, installation_id: Account::GLOBAL_APP_INSTALLATION_ID)
      end

      it { is_expected.to be true }
    end
  end

  describe "#current_state" do
    it "is set to initial state on new records" do
      account = build(:account)
      expect(account.attributes["current_state"]).to eq(AccountStateMachine.initial_state)
    end

    it "is not set to initial state on existing records" do
      account = create(:account, :active)

      loaded_from_db = described_class.find(account.id)
      expect(loaded_from_db.attributes["current_state"]).to eq("active")
    end

    it "is validated to be a known account state machine state" do
      account.current_state = "nonexistent_state"
      expect(account).not_to be_valid
    end
  end

  describe ".in_state" do
    it "uses the current_state column" do
      # create accounts with different states recorded in transition history
      # and the current_state column
      inactive_account = create(:account, :active).tap { |account| account.update!(current_state: :inactive) }
      active_account = create(:account).tap { |account| account.update!(current_state: :active) }

      results = described_class.in_state(:inactive).to_a

      expect(results).to include(inactive_account)
      expect(results).not_to include(active_account)
    end
  end

  describe ".not_in_state" do
    it "uses the current_state column" do
      # create accounts with different states recorded in transition history
      # and the current_state column
      inactive_account = create(:account, :active).tap { |account| account.update!(current_state: :inactive) }
      active_account = create(:account).tap { |account| account.update!(current_state: :active) }

      results = described_class.not_in_state(:inactive).to_a

      expect(results).to include(active_account)
      expect(results).not_to include(inactive_account)
    end
  end
end
