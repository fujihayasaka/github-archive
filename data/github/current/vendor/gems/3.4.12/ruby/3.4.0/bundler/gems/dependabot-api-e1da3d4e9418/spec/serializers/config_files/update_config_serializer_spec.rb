# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConfigFiles::UpdateConfigSerializer, type: :serializer do
  let(:update_config) { FactoryBot.build_stubbed(:update_config) }
  let(:serialized_update_config) { described_class.new(update_config) }

  let(:hash_output) { serialized_update_config.to_h.deep_stringify_keys }

  describe "#package_ecosystem" do
    subject { serialized_update_config.package_ecosystem }

    it { is_expected.to eq("bundler") }

    it "is included in the serialized hash" do
      expect(hash_output.keys).to include("package_ecosystem")
    end
  end

  describe "#target_branch" do
    subject { serialized_update_config.target_branch }

    context "when not set" do
      it "isn't included in the serialized hash" do
        expect(hash_output.keys).not_to include("target_branch")
      end

      context "but default values have been requested" do
        let(:serialized_update_config) do
          described_class.new(update_config, include_defaults: true)
        end

        it { is_expected.to eq("master") }

        it "is included in the serialized hash" do
          expect(hash_output.keys).to include("target_branch")
        end
      end
    end

    context "when set" do
      before { update_config.target_branch = "custom_branch" }

      it { is_expected.to eq("custom_branch") }

      it "is included in the serialized hash" do
        expect(hash_output.keys).to include("target_branch")
      end
    end
  end

  describe "#schedule" do
    subject { serialized_update_config.schedule }

    it { is_expected.to eq("interval" => "daily") }

    it "is included in the serialized hash" do
      expect(hash_output.keys).to include("schedule")
    end
  end

  describe "#assignees" do
    subject { serialized_update_config.assignees }

    context "when not set" do
      it "isn't included in the serialized hash" do
        expect(hash_output.keys).not_to include("assignees")
      end

      context "but default values have been requested" do
        let(:serialized_update_config) do
          described_class.new(update_config, include_defaults: true)
        end

        it { is_expected.to eq([]) }

        it "is included in the serialized hash" do
          expect(hash_output.keys).to include("assignees")
        end
      end
    end

    context "when set" do
      before { update_config.default_assignees = ["greysteil"] }

      it { is_expected.to eq(["greysteil"]) }

      it "is included in the serialized hash" do
        expect(hash_output.keys).to include("assignees")
      end
    end
  end

  describe "#labels" do
    subject { serialized_update_config.labels }

    context "when not set" do
      it "isn't included in the serialized hash" do
        expect(hash_output.keys).not_to include("labels")
      end

      context "but default values have been requested" do
        let(:serialized_update_config) do
          described_class.new(update_config, include_defaults: true)
        end

        it { is_expected.to eq(["dependencies"]) }

        it "is included in the serialized hash" do
          expect(hash_output.keys).to include("labels")
        end
      end
    end

    context "when set" do
      before { update_config.custom_labels = ["sec"] }

      it { is_expected.to eq(["sec"]) }

      it "is included in the serialized hash" do
        expect(hash_output.keys).to include("labels")
      end
    end
  end

  describe "#versioning_strategy" do
    subject { serialized_update_config.versioning_strategy }

    it { is_expected.to eq("auto") }

    it "isn't included in the serialized hash" do
      expect(hash_output.keys).not_to include("versioning_strategy")
    end

    context "when default values have been requested" do
      let(:serialized_update_config) do
        described_class.new(update_config, include_defaults: true)
      end

      it "is included in the serialized hash" do
        expect(hash_output.keys).to include("versioning_strategy")
      end

      context "for a package manager that doesn't support custom strategies" do
        before { update_config.package_manager = "maven" }

        it "is not included in the serialized hash" do
          expect(hash_output.keys).not_to include("versioning_strategy")
        end

        context "but does have a lockfile" do
          before { update_config.package_manager = "pip" }

          it "is included in the serialized hash" do
            expect(hash_output.keys).to include("versioning_strategy")
          end
        end
      end
    end

    context "when only lockfile updates are enabled" do
      before { update_config.lockfile_only = true }

      it { is_expected.to eq("lockfile-only") }

      it "is included in the serialized hash" do
        expect(hash_output.keys).to include("versioning_strategy")
      end
    end

    context "when a specific strategy is set" do
      before { update_config.requirements_update_strategy = "bump_versions" }

      it { is_expected.to eq("increase") }

      it "is included in the serialized hash" do
        expect(hash_output.keys).to include("versioning_strategy")
      end
    end
  end

  describe "#allow" do
    subject { serialized_update_config.allow }

    it "builds the correct allow array" do
      expect(subject).to eq(
        [
          {
            "dependency-type" => "direct",
          },
        ],
      )
    end

    it "isn't included in the serialized hash" do
      expect(hash_output.keys).not_to include("allow")
    end

    context "when default values have been requested" do
      let(:serialized_update_config) do
        described_class.new(update_config, include_defaults: true)
      end

      it "isn't included in the serialized hash" do
        expect(hash_output.keys).to include("allow")
      end
    end

    context "when aa dependency whitelist has been specified" do
      before do
        update_config.allowed_updates = [
          { "dependency_name" => "i18n" },
        ]
      end

      it "serializes whitelist" do
        expect(subject).to eq(
          [
            { "dependency-name" => "i18n" },
          ],
        )
      end

      it "is included in the serialized hash" do
        expect(hash_output.keys).to include("allow")
      end
    end

    context "when a dependency whitelist has been specified enabled" do
      before do
        update_config.allowed_updates = [{ "dependency_name" => "i18n" }]
      end

      it { is_expected.to eq([{ "dependency-name" => "i18n" }]) }

      it "is included in the serialized hash" do
        expect(hash_output.keys).to include("allow")
      end
    end
  end

  describe "#ignore" do
    subject(:ignore) { serialized_update_config.ignore }

    it { is_expected.to eq([]) }

    it "isn't included in the serialized hash" do
      expect(hash_output.keys).not_to include("ignore")
    end

    context "when default values have been requested" do
      let(:serialized_update_config) do
        described_class.new(update_config, include_defaults: true)
      end

      it "is included in the serialized hash" do
        expect(hash_output.keys).to include("ignore")
      end
    end

    context "with an ignore condition specified" do
      let(:update_config) { FactoryBot.build(:update_config) }
      let(:from_config_file) { false }

      before do
        FactoryBot.create(
          :ignore_condition,
          update_config: update_config,
          dependency_name: "rails",
          version_requirement: ">= 6.0",
          from_config_file: from_config_file,
        )
      end

      it "builds the array correctly" do
        expect(ignore).
          to eq(
            [
              {
                "dependency-name" => "rails",
                "versions" => [">= 6.0"],
              },
            ],
          )
      end

      it "isn't included in the serialized hash" do
        expect(hash_output.keys).not_to include("ignore")
      end

      context "in the config file" do
        let(:from_config_file) { true }

        it "is included in the serialized hash" do
          expect(hash_output.keys).to include("ignore")
        end
      end
    end
  end

  describe "#commit_message" do
    subject { serialized_update_config.commit_message }

    context "when not set" do
      it "isn't included in the serialized hash" do
        expect(hash_output.keys).not_to include("commit_message")
      end

      context "but default values have been requested" do
        let(:serialized_update_config) do
          described_class.new(update_config, include_defaults: true)
        end

        # TODO: We currently treat `nil` as auto, but in future we might want to
        # automatically detect the commit prefix and store it. If we do that we
        # should show it here
        it "isn't included in the serialized hash" do
          expect(hash_output.keys).not_to include("commit_message")
        end
      end
    end

    context "when a commit prefix is set" do
      before { update_config.commit_message_prefix = "chore" }

      it { is_expected.to eq("prefix" => "chore") }

      it "is included in the serialized hash" do
        expect(hash_output.keys).to include("commit_message")
        expect(hash_output["commit_message"]).to eq("prefix" => "chore")
      end

      context "and include_scope is set, too" do
        before { update_config.commit_message_include_scope = true }

        it { is_expected.to eq("prefix" => "chore", "include" => "scope") }
      end

      context "and prefix_development is set, too" do
        before { update_config.commit_message_prefix_development = "fix" }

        it do
          expect(subject).to eq("prefix" => "chore", "prefix-development" => "fix")
        end
      end
    end

    context "when only include_scope is set" do
      before { update_config.commit_message_include_scope = true }

      it "isn't included in the serialized hash" do
        expect(hash_output.keys).not_to include("commit_message")
      end
    end
  end

  describe "#cooldown" do
    subject { serialized_update_config.cooldown }

    context "when not set" do
      it "isn't included in the serialized hash" do
        expect(hash_output.keys).not_to include("cooldown")
      end
    end

    context "when set" do
      let(:cooldown_settings) do
        {
          "default-days" => 7,
          "semver-major-days" => 0,
          "semver-minor-days" => 0,
          "semver-patch-days" => 0,
          "include" => [],
          "exclude" => [],
        }
      end

      before do
        FactoryBot.create(
          :update_config_cooldown,
          update_config: update_config,
          default_days: 7,
        )
      end

      it { is_expected.to eq(cooldown_settings) }

      it "is included in the serialized hash" do
        expect(hash_output.keys).to include("cooldown")
      end
    end
  end
end
