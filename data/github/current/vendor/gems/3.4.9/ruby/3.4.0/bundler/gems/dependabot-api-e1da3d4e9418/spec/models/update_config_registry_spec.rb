# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateConfigRegistry, type: :model do
  describe "#registry" do
    subject(:uc_registry) do
      described_class.new(update_config: update_config, registry_name: registry_name)
    end

    let(:update_config) { FactoryBot.build(:update_config) }
    let(:registry_name) { "my-registry" }

    it "raises error when not found" do
      expect { uc_registry.registry }.to raise_error(UpdateConfigRegistry::RegistryNotFound)
    end

    it "returns Repo-owned registry" do
      reg = FactoryBot.create(:registry, source: update_config.repo, name: registry_name)
      expect(uc_registry.registry).to eq(reg)
    end

    it "returns Account-owned registry" do
      reg = FactoryBot.create(:registry, source: update_config.repo.account, name: registry_name)
      expect(uc_registry.registry).to eq(reg)
    end
  end
end
