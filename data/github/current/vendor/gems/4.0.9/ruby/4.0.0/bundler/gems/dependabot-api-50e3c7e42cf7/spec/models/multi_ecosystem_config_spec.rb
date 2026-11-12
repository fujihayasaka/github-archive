# frozen_string_literal: true

require "rails_helper"

RSpec.describe MultiEcosystemConfig do
  describe "#normalised_name" do
    it "returns the name lowercased with special characters replaced by underscores" do
      config = described_class.new(name: "My Multi-Ecosystem! 2025")
      expect(config.normalised_name).to eq("my_multi_ecosystem_2025")
    end

    it "handles names with only special characters" do
      config = described_class.new(name: "!!!")
      expect(config.normalised_name).to eq("_")
    end

    it "handles names with spaces and mixed case" do
      config = described_class.new(name: "Hello World Test")
      expect(config.normalised_name).to eq("hello_world_test")
    end

    it "handles names with numbers and underscores" do
      config = described_class.new(name: "Test_123")
      expect(config.normalised_name).to eq("test_123")
    end

    describe "#update_config_siblings" do
      let(:multi_ecosystem_config) { create(:multi_ecosystem_config) }
      let!(:update_configs) { create_list(:update_config, 2, :active, multi_ecosystem_config: multi_ecosystem_config) }

      it "returns the siblings of the first update_config" do
        expect(multi_ecosystem_config.update_config_siblings).to match_array(update_configs)
      end

      context "when there are no update_configs" do
        let(:multi_ecosystem_config_without_configs) { create(:multi_ecosystem_config) }

        it "returns an empty array" do
          expect(multi_ecosystem_config_without_configs.update_config_siblings).to be_empty
        end
      end
    end
  end
end
