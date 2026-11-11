# frozen_string_literal: true

require "rails_helper"

RSpec.describe DependencyGroup, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  describe "validations" do
    it "requires a name to be present" do
      unnamed_group = build_stubbed(:dependency_group, name: "")

      expect(unnamed_group).not_to be_valid
      expect(unnamed_group.errors[:name]).to include("can't be blank")
    end

    it "requires rules to be present" do
      no_rules_group = build_stubbed(:dependency_group, rules: nil)

      expect(no_rules_group).not_to be_valid
      expect(no_rules_group.errors[:rules]).to include("can't be blank")
    end

    it "requires rules to be a hash" do
      bad_rules_group = build_stubbed(:dependency_group, rules: "a string instead")

      expect(bad_rules_group).not_to be_valid
      expect(bad_rules_group.errors[:rules]).to include("must be a Hash")
    end

    it "requires rules to have at least one base rule defined" do
      bad_rules_group = build_stubbed(:dependency_group, rules: { rhymes_with: ["tails"] })

      expect(bad_rules_group).not_to be_valid
      expect(bad_rules_group.errors[:rules]).to include(
        "must include one of 'dependency-type, patterns, update-types, exclude-patterns'"
      )
    end

    it "must belong to an update config" do
      orphan_group = build_stubbed(:dependency_group, name: "no config", update_config: nil)

      expect(orphan_group).not_to be_valid
      expect(orphan_group.errors[:update_config]).to include("must exist")
    end

    it "ensures an update config has uniquely named groups" do
      update_config = create(:update_config)
      name = "my_group"
      original = create(:dependency_group, name: name, update_config: update_config)

      duplicate = build(:dependency_group, name: original.name, update_config: original.update_config)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include("has already been taken")
    end

    it "does not include logically deleted groups in uniqueness validation" do
      update_config = create(:update_config)
      name = "my_group"
      deleted = create(:dependency_group, name: name, update_config: update_config)
      deleted.delete

      replacement = build(:dependency_group, name: deleted.name, update_config: deleted.update_config)

      expect(replacement).to be_valid
    end

    it "allows multiple deleted rows with the same name" do
      update_config = create(:update_config)
      name = "my_group"
      deleted1 = create(:dependency_group, name: name, update_config: update_config)
      deleted1.delete

      deleted2 = create(:dependency_group, name: name, update_config: update_config)
      deleted2.delete
      expect(deleted2).to be_valid
    end

    it "ensures that name uniqueness is checked after formatting" do
      update_config = create(:update_config)
      original = create(:dependency_group, name: "my-group", update_config: update_config)

      duplicate = build(:dependency_group, name: "My Group", update_config: original.update_config)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include("has already been taken")
    end

    it "allows an update config's group to be created if it is uniqueley named" do
      update_config = create(:update_config)
      group = build(:dependency_group, name: "my_group", update_config: update_config)

      expect(group).to be_valid
    end

    it "requires applies_to to be a valid value" do
      group = build_stubbed(:dependency_group, applies_to: "invalid_value")

      expect(group).not_to be_valid
      expect(group.errors[:applies_to]).to include("invalid_value must be one of version-updates, security-updates")
    end
  end

  describe "#name" do
    it "ensures the name is parameterized" do
      # The accented ö is not permitted by our JSON schema so this should not
      # happen, but let's be clear we failover to latin characters per Rails'
      # parameterization.
      group = create(:dependency_group, name: "My Awesome Gröup")

      expect(group.name).to eql("my-awesome-group")
    end
  end

  describe "#rules" do
    it "does not filter out permitted rules" do # rubocop:disable RSpec/ExampleLength
      group = create(
        :dependency_group,
        name: "pebkac",
        rules: {
          "patterns" => [
            "*",
          ],
          "exclude-patterns" => [
            "not-you",
          ],
          "dependency-type" => [
            "production",
          ],
        }
      )

      expect(group.rules.keys).to eql(%w(patterns exclude-patterns dependency-type))
    end

    it "filters out junk rules" do
      group = create(
        :dependency_group,
        name: "pebkac",
        rules: {
          "patterns" => [
            "I did this bit right",
          ],
          "excludes" => [
            "But I forgot the name of this key",
          ],
        }
      )

      expect(group.rules.keys).to eql(["patterns"])
    end

    context "with an update-types rule" do
      let(:config) { create(:update_config) }

      it "does not filter out update-types" do
        group = create(
          :dependency_group,
          update_config: config,
          name: "pebkac",
          rules: {
            "patterns" => ["*"],
            "update-types" => ["minor"],
          }
        )

        expect(group.rules.keys).to eql(%w(patterns update-types))
      end
    end
  end

  describe "#serialize" do
    it "translates the group into a consumable Hash" do
      name = "donny"
      rules = {
        "patterns" => ["*"],
        "update-types" => ["major"],
      }
      applies_to = described_class::APPLIES_TO_SECURITY_UPDATES
      group = create(:dependency_group, name: name, rules: rules, applies_to: applies_to)

      expect(group.serialize).
        to eq(
          {
            "name" => name,
            "rules" => rules,
            "applies-to" => applies_to,
          }
        )
    end
  end

  context "logical deletion" do
    describe "#destroy" do
      it "cannot be used to remove a record" do
        group = create(:dependency_group)

        expect(group.destroy).to be false
        expect { group.destroy }.not_to change(described_class, :count)
      end
    end

    describe "#delete" do
      it "sets the deleted_at date on the DependencyGroup" do
        group = create(:dependency_group)

        expect { group.delete }.to change(group, :deleted?).from(false).to(true)

        expect(group.reload.deleted_at).to be_a(Time)
      end

      it "does not change the deleted_at value if called a second time" do
        group = travel_to(5.days.ago) do
          create(:dependency_group, :deleted)
        end

        expect { group.delete }.not_to change(group, :deleted_at)

        expect(group.reload.deleted_at).to be_a(Time)
      end
    end

    describe "::delete_all" do
      it "can be used to force the removal of records" do
        group = create(:dependency_group)

        expect { described_class.where(id: group.id).delete_all }.to change(described_class, :count).from(1).to(0)
      end
    end

    describe "::active" do
      it "excludes deleted groups" do
        group1 = create(:dependency_group)
        group2 = create(:dependency_group)

        group1.delete

        expect(described_class.active).not_to include(group1)
        expect(described_class.active).to include(group2)
      end
    end

    describe "::ordered" do
      it "sorts groups using the customer-defined ordering" do
        first = create(:dependency_group, sort_order: 1)
        second = create(:dependency_group, sort_order: 1_000)

        expect(described_class.ordered).not_to eq([second, first])
        expect(described_class.ordered).to eq([first, second])
      end
    end

    describe "cleaning up pull requests" do
      it "enqueues a cleanup job when a group is first deleted" do
        group = create(:dependency_group)

        expect { group.delete }.to have_enqueued_job(CleanupDependencyGroupPullRequestsJob).with(group.id)
      end

      it "enqueues a cleanup job if the row is deleted via the update method" do
        group = create(:dependency_group)

        expect { group.update(deleted_at: Time.now.utc) }.
          to have_enqueued_job(CleanupDependencyGroupPullRequestsJob).with(group.id)
      end

      it "does not enqueue a cleanup job if called a second time on a deleted group" do
        group = create(:dependency_group, :deleted)

        expect { group.delete }.not_to have_enqueued_job(CleanupDependencyGroupPullRequestsJob)
      end

      it "does not enqueue a cleanup job if the deleted_at date is modified via update" do
        group = travel_to(5.days.ago) do
          create(:dependency_group, :deleted)
        end

        expect { group.update(deleted_at: Time.now.utc) }.
          not_to have_enqueued_job(CleanupDependencyGroupPullRequestsJob)
      end

      it "does not enqueue a cleanup job on unrelated updates" do
        group = create(:dependency_group)

        expect { group.update(name: "unrelated-changes") }.
          not_to have_enqueued_job(CleanupDependencyGroupPullRequestsJob)
      end
    end
  end
end
