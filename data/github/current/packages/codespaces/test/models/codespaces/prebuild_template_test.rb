# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesPrebuildTemplateTest < GitHub::TestCase
  include CodespacesPlanFixtures

  def setup
    enable_feature_flag(:codespaces_prebuild_template_plan_backfill)
    disable_feature_flag(:codespaces_local_target_url_valid)
  end

  context "#plan" do
    test "is looked up from the location and target when plan_id is nil" do
      location = "WestEurope"
      vscs_target = "local"
      plan = Codespaces::Plan.for(location: location, vscs_target: vscs_target)

      template = Codespaces::PrebuildTemplate.new vscs_target: vscs_target, location: location

      found_plan = template.plan

      refute_nil found_plan
      assert_equal plan, found_plan
    end

    test "is invalid when no matching plan exists" do
      template = Codespaces::PrebuildTemplate.new vscs_target: "production", location: "TanagraEast"

      refute_predicate template, :valid?

      assert_equal template.errors[:plan], ["No plan found for location and vscs_target"]
    end

    test "is is not looked up from the location and target when plan_id is present" do
      location = "WestEurope"
      vscs_target = "local"
      plan = Codespaces::Plan.for(location: location, vscs_target: vscs_target)
      plan2 = Codespaces::Plan.for(location: "WestEurope", vscs_target: :production)
      template = Codespaces::PrebuildTemplate.new vscs_target: vscs_target, location: location, plan: plan2

      refute_nil template.plan
      assert_equal plan2, template.plan
    end

    test "is is looked up from the location and target when plan_id is present when FF is off" do
      disable_feature_flag(:codespaces_prebuild_template_plan_backfill)
      location = "WestEurope"
      vscs_target = "local"
      plan = Codespaces::Plan.for(location: location, vscs_target: vscs_target)
      plan2 = Codespaces::Plan.for(location: "WestEurope", vscs_target: :production)
      template = Codespaces::PrebuildTemplate.new vscs_target: vscs_target, location: location, plan: plan2

      refute_nil template.plan
      assert_equal plan, template.plan
    end
  end

  context "#vscs_target" do
    test "is converted to a symbol" do
      template = build(:codespace_prebuild_template)

      template.vscs_target = "production"
      assert_equal :production, template.vscs_target

      template.vscs_target = "local"
      assert_equal :local, template.vscs_target
    end

    test "an empty vscs target is set to production" do
      template = create(:codespace_prebuild_template, vscs_target: nil, branch: "master")
      assert_equal :production, template.vscs_target
    end
  end

  context "#vscs_target_url" do
    test "is required for the local target" do
      local_template = build(
        :codespace_prebuild_template,
        vscs_target: :local,
        branch: "master",
        vscs_target_url: "http://localhost.example.com/",
        configuration: create(:codespace_prebuild_configuration, vscs_target: :local, vscs_target_url: "http://localhost.example.com/")
      )

      assert_predicate local_template, :valid?

      local_template.vscs_target_url = nil
      refute_predicate local_template, :valid?
      assert_includes local_template.errors.full_messages, "Vscs target url must be present when vscs_target is local"
    end

    test "is forbidden for non-local targets" do
      production_template = build(
        :codespace_prebuild_template,
        vscs_target: :production,
        branch: "master",
      )

      production_template.vscs_target_url = nil
      assert_predicate production_template, :valid?

      production_template.vscs_target_url = "http://localhost.example.com"
      refute_predicate production_template, :valid?
      assert_includes production_template.errors.full_messages, "Vscs target url must be blank when vscs_target is not local"
    end

    test "throws error if vscs target is local and vscs target url is invalid" do
      enable_feature_flag(:codespaces_local_target_url_valid)
      prebuild_template = build(:codespace_prebuild_template, vscs_target: :local, vscs_target_url: "http://localhost:8080")
      refute_predicate prebuild_template, :valid?
      assert_includes prebuild_template.errors[:vscs_target_url], "must be a valid local target URL"
    end

    test "creates record if vscs target is local and vscs target url is valid" do
      enable_feature_flag(:codespaces_local_target_url_valid)
      prebuild_template = build(
        :codespace_prebuild_template,
        vscs_target: :local,
        vscs_target_url: "https://codespaces.servicebus.windows.net/monalisa",
        branch: "master",
        configuration: create(:codespace_prebuild_configuration, vscs_target: :local, vscs_target_url: "https://codespaces.servicebus.windows.net/monalisa")
      )
      assert_predicate prebuild_template, :valid?
      assert_equal prebuild_template.vscs_target, :local
    end
  end

  context "#name" do
    test "generates name with schema with underscores to avoid collisions with Codespace names" do
      assert_includes create(:codespace_prebuild_template, branch: "master").name, "prebuild_template_"
    end

    test "throws error in cases of name collision" do
      create(:codespace_prebuild_template, name: "samename", branch: "master")
      prebuild_template = build(:codespace_prebuild_template, name: "samename", branch: "master")
      assert_raises ActiveRecord::RecordInvalid do
        prebuild_template.save!
      end
      refute_predicate prebuild_template, :valid?
      assert_includes prebuild_template.errors[:name], "has already been taken"
    end
  end

  context "billing entry tests" do
    test "test that prebuild template billing entry is created when prebuild template is created" do
      template = create(:codespace_prebuild_template, branch: "master")
      assert_predicate template, :valid?
      assert_equal true, template.id.present?
      assert_equal true, template.guid.present?

      template = template.reload

      assert_equal true, template.billing_entry.present?

      # Check that fields of billing entry are present as well
      assert_equal true, template.billing_entry.billable_owner.present?
      assert_equal true, template.billing_entry.prebuild_template_guid.present?
      assert_equal true, template.billing_entry.prebuild_template_id.present?
      assert_equal true, template.billing_entry.prebuild_plan_name.present?
      assert_equal true, template.billing_entry.prebuild_created_at.present?
      assert_equal true, template.billing_entry.repository.present?
      assert_equal false, template.billing_entry.prebuild_deleted_at.present?
    end

    test "prebuild template billing entry updates prebuild_deleted_at when destroy is called" do
      template = create(:codespace_prebuild_template, id: SecureRandom.uuid, branch: "master")
      assert_predicate template, :valid?
      assert_equal true, template.id.present?
      assert_equal true, template.guid.present?

      template = template.reload
      assert_equal true, template.billing_entry.present?

      # Destroy the template
      template.destroy!

      billing_entry = Codespaces::PrebuildTemplateBillingEntry.latest(template.guid)

      # Check that prebuild_deleted_at was updated
      assert_equal true, billing_entry.billable_owner.present?
      assert_equal true, billing_entry.prebuild_template_guid.present?
      assert_equal true, billing_entry.prebuild_template_id.present?
      assert_equal true, billing_entry.prebuild_plan_name.present?
      assert_equal true, billing_entry.prebuild_created_at.present?
      assert_equal true, billing_entry.repository.present?
      assert_equal true, billing_entry.prebuild_deleted_at.present?
    end
  end

  context "callbacks" do
    test "validates the configuration exists" do
      assert_raises ActiveRecord::RecordInvalid do
        create(:codespace_prebuild_template, configuration: nil)
      end
    end
    test "validates the configuration matches the location" do
      assert_raises ActiveRecord::RecordInvalid do
        create(
          :codespace_prebuild_template,
          location: "WestEurope",
          configuration: create(:codespace_prebuild_configuration, with_locations: ["EastUs"])
        )
      end
    end
    test "validates the configuration matches the branch" do
      assert_raises ActiveRecord::RecordInvalid do
        create(
          :codespace_prebuild_template,
          branch: "main",
          configuration: create(:codespace_prebuild_configuration, branch: "different")
        )
      end
    end
    test "validates the configuration matches the devcontainer_path" do
      assert_raises ActiveRecord::RecordInvalid do
        create(
          :codespace_prebuild_template,
          devcontainer_path: ".devcontainer.json",
          configuration: create(:codespace_prebuild_configuration, devcontainer_path: ".devcontainer/other")
        )
      end
    end
    test "validates the configuration matches the devcontainer_path when prebuild template is nil and config uses a default path" do
      assert_nothing_raised do
        create(
          :codespace_prebuild_template,
          devcontainer_path: nil,
          branch: "master",
          configuration: create(:codespace_prebuild_configuration, devcontainer_path: ".devcontainer.json")
        )
      end
    end
    test "validates the configuration matches the vscs_target" do
      assert_raises ActiveRecord::RecordInvalid do
        create(
          :codespace_prebuild_template,
          vscs_target: "production",
          configuration: create(:codespace_prebuild_configuration, vscs_target: "ppe")
        )
      end
    end
  end
end
