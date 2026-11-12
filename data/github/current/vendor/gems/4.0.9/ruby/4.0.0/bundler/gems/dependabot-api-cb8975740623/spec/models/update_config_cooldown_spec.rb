# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateConfigCooldown do
  describe "#cooldown_settings" do
    subject(:uc_cooldown) do
      described_class.new(
        update_config: update_config,
        default_days: default_days,
        semver_major_days: semver_major_days,
        semver_minor_days: semver_minor_days,
        semver_patch_days: semver_patch_days,
        include: include,
        exclude: exclude
      )
    end

    let(:update_config) { build(:update_config) }
    let(:default_days) { 7 }
    let(:semver_major_days) { 14 }
    let(:semver_minor_days) { 7 }
    let(:semver_patch_days) { 1 }
    let(:include) { ["dependency1"] }
    let(:exclude) { ["dependency2"] }

    it "returns the correct cooldown settings" do
      expect(uc_cooldown.cooldown_settings).to eq(
        "default-days" => 7,
        "semver-major-days" => 14,
        "semver-minor-days" => 7,
        "semver-patch-days" => 1,
        "include" => ["dependency1"],
        "exclude" => ["dependency2"]
      )
    end

    context "when include and exclude are nil" do
      let(:include) { nil }
      let(:exclude) { nil }

      it "returns empty arrays for include and exclude" do
        expect(uc_cooldown.cooldown_settings).to eq(
          "default-days" => 7,
          "semver-major-days" => 14,
          "semver-minor-days" => 7,
          "semver-patch-days" => 1,
          "include" => [],
          "exclude" => []
        )
      end
    end

    context "when days are nil" do
      let(:default_days) { nil }
      let(:semver_major_days) { nil }
      let(:semver_minor_days) { nil }
      let(:semver_patch_days) { nil }

      it "returns 0 for days" do
        expect(uc_cooldown.cooldown_settings).to eq(
          "default-days" => 0,
          "semver-major-days" => 0,
          "semver-minor-days" => 0,
          "semver-patch-days" => 0,
          "include" => ["dependency1"],
          "exclude" => ["dependency2"]
        )
      end
    end
  end
end
