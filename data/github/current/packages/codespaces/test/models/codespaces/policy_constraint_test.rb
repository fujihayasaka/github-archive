# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesPolicyConstraintTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @org = create(:organization)
    @org_repo = create(:repository, owner: @org)
    @policy_group = Codespaces::PolicyGroup.create!(
      owner: @org,
      owner_type: "User",
      name: "My Test Policies",
    )

    @params = {
      repo: @org_repo.name_with_owner,
      branch: "main",
      path: "host-setup.sh"
    }

  end

  context "configuration" do
    test "all constraints have a value type" do
      Codespaces::PolicyConstraint.names.each do |name, _|
        assert Codespaces::PolicyConstraint::CONSTRAINT_CONFIGURATION.dig(name, :type), "Expected a value type for constraint #{name}"
      end
    end

    test "all allowed_values-type constraints have an allowable_values_options set, or take custom values" do
      Codespaces::PolicyConstraint::CONSTRAINT_CONFIGURATION.each do |name, config|
        value_type = config[:type]
        if value_type == Codespaces::PolicyConstraint::TYPE_ALLOWED_VALUES
          assert(
            config[:custom_allowed_values] || config[:allowable_values_options],
            "Expected a set of allowed values for constraint #{name}"
          )
        end
      end
    end

    test ".config_for_policy_owner specifies allowable/max allowable values" do
      base_config = Codespaces::PolicyConstraint::CONSTRAINT_CONFIGURATION
      assert base_config[Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES][:allowable_values_options].count > 0
      assert_equal Codespaces::Tier::CODESPACES_PER_USER, base_config[Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS][:maximum_allowable_value]


      Codespaces::Skus::Sku.any_instance.stubs(:allowable_by_policy_owner?).returns(false)
      Codespaces::Tier.stub_const(:CODESPACES_PER_USER, 0) do
        config = Codespaces::PolicyConstraint.config_for_policy_owner(@org)

        assert_equal 0, config[Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES][:allowable_values].count
        assert_equal 0, config[Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS][:maximum_allowable_value]
      end
    end
  end

  context "validation" do
    test "disallows an undefined constraint name" do
      assert_raises ArgumentError do
        Codespaces::PolicyConstraint.new(
          policy_group: @policy_group,
          name: "foo",
          enabled_value: true,
        )
      end
    end

    test "disallows conflicting constraints for a PolicyGroup" do
      constraint1 = Codespaces::PolicyConstraint.create!(
        policy_group: @policy_group,
        name: "codespaces.allowed_machine_types",
        allowed_values: [],
      )

      constraint2 = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_machine_types",
        allowed_values: [],
      )

      refute constraint2.valid?
      assert constraint2.errors[:name].any?, "Expected constraint name to be taken for the owning policy_group"
    end

    test "disallows two types of specified values" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_machine_types",
        allowed_values: [],
        enabled_value: true,
      )

      refute constraint.valid?
      assert constraint.errors[:base].any?, "Expected constraint to be invalid since it has two types of values defined"
    end

    test "disallows inappropriate value for a given constraint name" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_machine_types",
        enabled_value: true,
      )

      refute constraint.valid?
      assert constraint.errors[:allowed_values].any?, "Expected an allowed_values constraint to be invalid since it specified an enabled_value"
    end

    test "disallows inappropriate value type for a given constraint name" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_machine_types",
        value_type: Codespaces::PolicyConstraint::TYPE_ENABLED,
        allowed_values: [],
      )

      refute constraint.valid?
      assert constraint.errors[:value_type].any?, "Expected an allowed_values constraint to be invalid since it specified a type_enabled value_type"
    end

    test "disallows extraneous allowed_values" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_machine_types",
        allowed_values: ["madeUpMachineType"],
      )

      refute constraint.valid?
      assert constraint.errors[:allowed_values].any?, "Expected constraint to be invalid since it includes an unexpected value"
    end

    test "allows value if FF into for machine type" do
      enable_feature_flag(:codespaces_linux_x_large, @policy_group.owner)
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_machine_types",
        allowed_values: ["xLargePremiumLinux"],
      )
      constraint.valid?
      assert_empty constraint.errors
      assert constraint.valid?
    end

    test "disallows value if not FF into for machine type" do
      disable_feature_flag(:codespaces_linux_x_large, @policy_group.owner)
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_machine_types",
        allowed_values: ["xLargePremiumLinux"],
      )
      refute constraint.valid?
    end

    test "it disallows a maximum idle timeout policy constraint that is nil" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_maximum_idle_timeout",
        maximum_value: nil,
      )

      refute constraint.valid?
      assert constraint.errors[:maximum_value].any?, "must be a number between 5 and 240 minutes"
    end

    test "it disallows a maximum idle timeout policy constraint that is greater than the maximum allowable 240 minutes" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_maximum_idle_timeout",
        maximum_value: 241,
      )

      refute constraint.valid?
      assert constraint.errors[:maximum_value].any?, "must be less than or equal to 240 minutes"
    end

    test "it allows a maximum idle timeout policy constraint that is equal to the maximum allowable 240 minutes" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_maximum_idle_timeout",
        maximum_value: 240,
      )

      assert constraint.valid?
    end

    test "it disallows a maximum idle timeout policy constraint that is less than the minimum allowable 5 minutes" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_maximum_idle_timeout",
        maximum_value: 4,
      )

      refute constraint.valid?
      assert constraint.errors[:maximum_value].any?, "must be greater than or equal to 5 minutes"
    end

    test "it allows a maximum idle timeout policy constraint that is equal to the minimum allowable 5 minutes" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_maximum_idle_timeout",
        maximum_value: 5,
      )

      assert constraint.valid?
    end

    test "it allows a maximum idle timeout policy constraint that is inbetween the minimum (5) and maximum (240) allowable minutes" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_maximum_idle_timeout",
        maximum_value: 120,
      )

      assert constraint.valid?
    end

    test "disallows port privacy policy allowed_values for machine type policy" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_machine_types",
        allowed_values: ["org"],
      )

      refute constraint.valid?
      assert constraint.errors[:allowed_values].any?, "Expected constraint to be invalid since it includes an unexpected value"
    end

    test "disallows maximum idle timeout policy allowed_values for machine type policy" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_machine_types",
        allowed_values: 30,
      )

      assert_raises_with_message(TypeError, "Array can't be coerced into Integer") do
        refute constraint.valid?
      end
      assert constraint.errors[:allowed_values].any?, "Expected constraint to be invalid since it includes an unexpected value"
    end

    test "disallows machine type policy allowed_values for port privacy policy" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_port_privacy_settings",
        allowed_values: ["basicLinux32gb"],
      )

      refute constraint.valid?
      assert constraint.errors[:allowed_values].any?, "Expected constraint to be invalid since it includes an unexpected value"
    end

    test "disallows maximum idle timeout policy allowed_values for port privacy policy" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_port_privacy_settings",
        allowed_values: 30,
      )

      assert_raises_with_message(TypeError, "Array can't be coerced into Integer") do
        refute constraint.valid?
      end
      assert constraint.errors[:allowed_values].any?, "Expected constraint to be invalid since it includes an unexpected value"
    end

    test "disallows port privacy policy values as maximum_value for maximum idle timeout" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_maximum_idle_timeout",
        maximum_value: ["org"],
      )

      refute constraint.valid?
      assert constraint.errors[:base].any?, "Must specify exactly one of: enabled_value, maximum_value, minimum_value, allowed_values"
    end

    test "disallows machine type policy values as maximum_value for maximum idle timeout" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_maximum_idle_timeout",
        maximum_value: ["basicLinux32gb"],
      )

      refute constraint.valid?
      assert constraint.errors[:base].any?, "Must specify exactly one of: enabled_value, maximum_value, minimum_value, allowed_values"
    end

    test "disallows values that are not valid container names" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_base_images",
        allowed_values: ["notarealimage!"],
      )

      refute constraint.valid?
      assert constraint.errors[:allowed_values].any?, "Invalid values were included: notarealimage!"
    end

    test "disallows empty values for container names" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_base_images",
        allowed_values: [""],
      )

      refute constraint.valid?
      assert constraint.errors[:allowed_values].any?, "All values must be a valid container image."
    end

    test "allows container names with * as prefix" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_base_images",
        allowed_values: ["ghcr.io/*"],
      )

      assert constraint.valid?
    end

    test "allows container names with * as prefix (2)" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_base_images",
        allowed_values: ["ghcr*"],
      )

      assert constraint.valid?
    end

    test "allows container names with '*' as prefix for tags (1)" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_base_images",
        allowed_values: ["ghcr.io/repo/image:*"],
      )

      assert constraint.valid?
    end

    test "allows container names with '*' as prefix for tags (2)" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_base_images",
        allowed_values: ["ghcr.io/repo/image:dev*"],
      )

      assert constraint.valid?
    end

    test "disallows container names if invalid (* is only allowed at the end)" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_base_images",
        allowed_values: ["ghcr.io/*/test"],
      )

      refute constraint.valid?
      assert constraint.errors[:allowed_values].any?, "Validation failed: Allowed values Invalid values were included: ghcr.io/*/test"
    end

    test "disallows container names if invalid (: at the end)" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_base_images",
        allowed_values: ["ghcr.io/repo/image:"],
      )

      refute constraint.valid?
      assert constraint.errors[:allowed_values].any?, "Validation failed: Allowed values Invalid values were included: ghcr.io/repo/image:"
    end

    test "disallows container names if invalid (* is only allowed at the end - 2)" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_base_images",
        allowed_values: ["ghc*rio/test"],
      )

      refute constraint.valid?
      assert constraint.errors[:allowed_values].any?, "Validation failed: Allowed values Invalid values were included: ghc*rio/test"
    end

    test "disallows container names if invalid (multiple *s are not allowed)" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_base_images",
        allowed_values: ["ghcr.io/*/*"],
      )

      refute constraint.valid?
      assert constraint.errors[:allowed_values].any?, "Validation failed: Allowed values Invalid values were included: ghcr.io/*/*"
    end

    test "disallows network configuration policy if no network configuration is selected" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.network_configuration",
      )

      refute constraint.valid?
      assert constraint.errors[:network_configuration].any?, "Validation failed: no network configuration selected"
    end

    test "disallows policy group targeting all repos with a network configuration when one already exists" do
      org = create(:organization)
      policy_group = create(:policy_group, :all_targets, owner: org, name: "Network Policy")

      params = {
        id: "some-network-config-id",
        name: "some-network-config-name",
      }

      create(:policy_constraint, policy_group: policy_group, params: params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION)
      colliding_policy_group = create(:policy_group, :all_targets, owner: org, name: "Another Network Policy")
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: colliding_policy_group,
        name: "codespaces.network_configuration",
        params: params
      )

      refute constraint.valid?
      assert constraint.errors[:network_configuration].any?
    end

    test "disallows policy group targeting a repo with a network configuration when that repo has already been targeted by another policy" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      policy_group = create(:policy_group, :selected_targets, targets: [repo], owner: org, name: "Network Policy")

      params = {
        id: "some-network-config-id",
        name: "some-network-config-name",
      }

      create(:policy_constraint, policy_group: policy_group, params: params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION)
      colliding_policy_group = create(:policy_group, :selected_targets, targets: [repo], owner: org, name: "Another Network Policy")
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: colliding_policy_group,
        name: "codespaces.network_configuration",
        params: params
      )

      refute constraint.valid?
      assert constraint.errors[:network_configuration].any?
    end
  end

  context "retention period" do
    test "it allows a maximum retention period policy constraint that is equal to the maximum allowable 30 days in minutes" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_maximum_retention_period",
        maximum_value: Codespace::MAX_RETENTION_PERIOD,
      )

      assert constraint.valid?
    end

    test "it disallows a maximum retention period policy constraint that is nil" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_maximum_retention_period",
        maximum_value: nil,
      )

      refute constraint.valid?
      assert constraint.errors[:maximum_value].any?, "must be a number between 0 and #{Codespace::MAX_RETENTION_PERIOD} minutes"
    end

    test "it disallows a maximum retention period policy constraint that is greater than the maximum allowable #{Codespace::MAX_RETENTION_PERIOD} minutes" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_maximum_retention_period",
        maximum_value: 43201,
      )

      refute constraint.valid?
      assert constraint.errors[:maximum_value].any?, "must be less than or equal to #{Codespace::MAX_RETENTION_PERIOD} minutes"
    end

    test "it disallows a maximum retention period policy constraint that is less than the minimum allowable 0 minutes" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_maximum_retention_period",
        maximum_value: -1,
      )

      refute constraint.valid?
      assert constraint.errors[:maximum_value].any?, "must be greater than or equal to 0 minutes"
    end
  end

  context "#audit_log_data" do
    test "machine type policy: allowed values are mapped to a display proc" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_machine_types",
        allowed_values: %w[premiumLinux largePremiumLinux],
      )
      assert_equal constraint.audit_log_data, { name: constraint.name, value: constraint.allowed_values, display_name: "Machine types", display_value: "8-core, 16-core" }
    end

    test "port privacy policy: allowed values are mapped to a display proc" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_port_privacy_settings",
        allowed_values: %w[org public],
      )
      assert_equal constraint.audit_log_data, { name: constraint.name, value: constraint.allowed_values, display_name: "Port privacy settings", display_value: "org, public" }
    end

    test "TYPE_MAXIMUM types are converted to strings on :value key" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_maximum_idle_timeout",
        maximum_value: 10,
      )
      assert_equal constraint.audit_log_data, { name: constraint.name, value: "10", display_name: "Maximum idle timeout", display_value: "10 minutes" }
    end
  end

  context "codespaces limit" do
    test "it disallows a maximum codespaces limit policy constraint that is nil" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_maximum_creations",
        maximum_value: nil,
      )

      refute constraint.valid?
    end

    test "disallows machine type policy values as maximum_value for maximum codespaces limit" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_maximum_creations",
        maximum_value: ["basicLinux32gb"],
      )

      refute constraint.valid?
      assert constraint.errors[:base].any?, "Must specify exactly one of: enabled_value, maximum_value, minimum_value, allowed_values"
    end

    test "it allows a maximum codespaces limit policy constraint for maximum (15)" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_maximum_creations",
        maximum_value: 15,
      )
      assert constraint.valid?
    end

    test "TYPE_MAXIMUM types are converted to strings on :value key" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_maximum_creations",
        maximum_value: 10,
      )
      display_name = Codespaces::PolicyConstraint::CONSTRAINT_CONFIGURATION.dig(constraint.name, :display_name)
      assert_equal constraint.audit_log_data, { name: constraint.name, value: "10", display_name:, display_value: 10 }
    end
  end

  context "host setup" do
    test "it disallows host setup policy constraint if params is nil" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: nil,
      )

      refute constraint.valid?
      assert constraint.errors[:host_setup].any?, "must be specified"
    end

    test "it disallows host setup policy constraint if required_keys not satisfied" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: {
          repo: @org_repo.name_with_owner,
          branch: "main",
          missingPath: "host-setup.sh"
        }
      )

      refute constraint.valid?
      assert_equal constraint.errors[:params].first, "Must specify repo, branch, path"
    end

    test "it allows host setup policy constraint with params" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: @params
      )

      assert constraint.valid?
      refute_nil constraint.params

      assert_equal @org_repo.name_with_owner, constraint.params["repo"]
      assert_equal "main", constraint.params["branch"]
      assert_equal "host-setup.sh", constraint.params["path"]
    end
  end

  context "validate_host_setup_config" do
    test "invalid if repo doesn't exist" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: {
          repo: "does-not-exist",
          branch: "main",
          path: "host-setup.sh"
        }
      )

      refute constraint.valid?
      assert_equal constraint.errors[:host_setup].first, "must specify a repository owned by the policy owner"
    end

    test "requires internal repo for enterprise policies" do
      business = create(:business)
      org = create(:organization, business:)
      repo = create(:private_repository, owner: org)
      policy_group = create(:policy_group, :all_targets, owner: business)

      constraint = Codespaces::PolicyConstraint.new(
        policy_group:,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: { repo: repo.name_with_owner, branch: "main", path: "host-setup.sh" }
      )

      refute constraint.valid?
      assert_equal constraint.errors[:host_setup].first, "must use a repository with internal visibility"
    end

    test "invalid if org doesn't exist" do
      org_new = create(:organization)
      repo = create(:repository, owner: org_new)

      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: {
          repo: "does-not-exist/#{repo.name}",
          branch: "main",
          path: "host-setup.sh"
        }
      )

      refute_equal org_new.login, "does-not-exist"
      refute constraint.valid?
      assert_equal constraint.errors[:host_setup].first, "must specify a repository owned by the policy owner"
    end

    test "errors if org policy owner doesn't own the repo" do
      org_new = create(:organization)
      repo = create(:repository, owner: org_new)

      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: {
          repo: repo.name_with_owner,
          branch: "main",
          path: "host-setup.sh"
        }
      )

      refute_equal org_new.login, @org.login
      refute constraint.valid?
      assert_equal constraint.errors[:host_setup].first, "must specify a repository owned by the policy owner"
    end

    test "errors if business policy owner doesn't own the repo" do
      business = create(:business)
      org_new = create(:organization)
      repo = create(:repository, owner: org_new)

      constraint = Codespaces::PolicyConstraint.new(
        policy_group: create(:policy_group, owner: business),
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: {
          repo: repo.name_with_owner,
          branch: "main",
          path: "host-setup.sh"
        }
      )

      refute_equal org_new.login, @org.login
      refute constraint.valid?
      assert_equal constraint.errors[:host_setup].first, "must specify a repository owned by the policy owner"
    end

    test "allows adding 'all orgs' for the first time" do
      business = create(:business)
      org = create(:organization, business:)
      repo = create(:private_repository, internal: true, owner: org)
      policy_group = create(:policy_group, :all_targets, owner: business)

      constraint = Codespaces::PolicyConstraint.new(
        policy_group:,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: { repo: repo.name_with_owner, branch: "main", path: "host-setup.sh" }
      )

      assert_equal 0, Codespaces::PolicyGroupMembership.joins(:policy_constraints).length
      assert constraint.valid?
    end

    test "allows updating constraint on an 'all orgs' policy" do
      business = create(:business)
      org = create(:organization, business:)
      repo = create(:private_repository, internal: true, owner: org)
      policy_group = create(:policy_group, :all_targets, owner: business)

      constraint = Codespaces::PolicyConstraint.create!(
        policy_group:,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: { repo: repo.name_with_owner, branch: "main", path: "host-setup.sh" }
      )

      constraint.update!(params: { repo: repo.name_with_owner, branch: "main", path: "host-setup2.sh" })
    end

    test "disallows a second 'all orgs' policy" do
      business = create(:business)
      org = create(:organization, business:)
      repo = create(:private_repository, internal: true, owner: org)
      policy_group = create(:policy_group, :all_targets, owner: business)

      Codespaces::PolicyConstraint.create!(
        policy_group:,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: { repo: repo.name_with_owner, branch: "main", path: "host-setup.sh" }
      )

      policy_group2 = create(:policy_group, :all_targets, name: "Second Policy", owner: business)

      constraint = Codespaces::PolicyConstraint.new(
        policy_group: policy_group2,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: { repo: repo.name_with_owner, branch: "main", path: "host-setup.sh" }
      )

      refute constraint.valid?
      assert_equal constraint.errors[:host_setup].first, "can only be added once for 'All organizations' policy target"
    end

    test "allows adding 'selected orgs' for the first time" do
      business = create(:business)
      org = create(:organization, business:)
      repo = create(:private_repository, internal: true, owner: org)
      policy_group = create(:policy_group, :selected_targets, targets: [org], owner: business)

      constraint = Codespaces::PolicyConstraint.new(
        policy_group:,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: { repo: repo.name_with_owner, branch: "main", path: "host-setup.sh" }
      )

      assert_equal 0, Codespaces::PolicyGroupMembership.joins(:policy_constraints).length
      assert constraint.valid?
    end

    test "allows updating constraint on a 'selected orgs' policy" do
      business = create(:business)
      org = create(:organization, business:)
      repo = create(:private_repository, internal: true, owner: org)
      policy_group = create(:policy_group, :selected_targets, targets: [org], owner: business)

      constraint = Codespaces::PolicyConstraint.create!(
        policy_group:,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: { repo: repo.name_with_owner, branch: "main", path: "host-setup.sh" }
      )

      constraint.update!(params: { repo: repo.name_with_owner, branch: "main", path: "host-setup2.sh" })
    end

    test "disallows a second 'selected orgs' policy targeting the same org" do
      business = create(:business)
      org = create(:organization, business:)
      repo = create(:private_repository, internal: true, owner: org)
      policy_group = create(:policy_group, :selected_targets, targets: [org], owner: business)

      Codespaces::PolicyConstraint.create!(
        policy_group:,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: { repo: repo.name_with_owner, branch: "main", path: "host-setup.sh" }
      )

      policy_group2 = create(:policy_group, :selected_targets, targets: [org], name: "Second Policy", owner: business)

      constraint = Codespaces::PolicyConstraint.new(
        policy_group: policy_group2,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: { repo: repo.name_with_owner, branch: "main", path: "host-setup.sh" }
      )

      refute constraint.valid?
      assert_equal constraint.errors[:host_setup].first, "can only be added once per organization"
    end

    test "allows adding 'all repos' for the first time" do
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: @params
      )

      assert_equal 0, Codespaces::PolicyGroupMembership.joins(:policy_constraints).length
      assert constraint.valid?
      refute_nil constraint.params

      assert_equal @org_repo.name_with_owner, constraint.params["repo"]
      assert_equal "main", constraint.params["branch"]
      assert_equal "host-setup.sh", constraint.params["path"]
    end

    test "allows adding 'all repos' for the first time - cross org" do
      org_new = create(:organization)
      repo_new = create(:private_repository, owner: org_new)
      policy_group_new = create(:policy_group, :all_targets, owner: org_new)

      params_new = {
        repo: repo_new.name_with_owner,
        branch: "main",
        path: "host-setup.sh"
      }

      create(:policy_constraint, policy_group: policy_group_new, params: params_new, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: @params
      )

      assert_equal 1, Codespaces::PolicyGroupMembership.joins(:policy_constraints).length
      assert constraint.valid?
      refute_nil constraint.params

      assert_equal @org_repo.name_with_owner, constraint.params["repo"]
      assert_equal "main", constraint.params["branch"]
      assert_equal "host-setup.sh", constraint.params["path"]
    end

    test "allows adding 'all repos' for the first time - cross org (1)" do
      org_new = create(:organization)
      repo_new = create(:private_repository, owner: org_new)
      policy_group_new = create(:policy_group, :selected_targets, targets: [repo_new], owner: org_new)

      params_new = {
        repo: repo_new.name_with_owner,
        branch: "main",
        path: "host-setup.sh"
      }

      create(:policy_constraint, policy_group: policy_group_new, params: params_new, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)

      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: @params
      )

      assert_equal 1, Codespaces::PolicyGroupMembership.joins(:policy_constraints).length
      assert constraint.valid?
      refute_nil constraint.params

      assert_equal @org_repo.name_with_owner, constraint.params["repo"]
      assert_equal "main", constraint.params["branch"]
      assert_equal "host-setup.sh", constraint.params["path"]
    end

    test "allows updating existing 'all repos' policy" do
      create(:policy_group_membership, policy_group: @policy_group, target: @org)
      create(:policy_constraint, policy_group: @policy_group, params: @params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)

      repo_2 = create(:private_repository, owner: @org)
      params_updated = {
        repo: repo_2.name_with_owner,
        branch: "main",
        path: "host-setup-2.sh"
      }

      @policy_group.apply_constraints!([{ name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP, value: params_updated.to_json }])
      assert_equal 1, @policy_group.policy_constraints.count

      constraint = @policy_group.policy_constraints.first
      assert_equal Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP, constraint.name
      assert_equal repo_2.name_with_owner, constraint.params["repo"]
      assert_equal "main", constraint.params["branch"]
      assert_equal "host-setup-2.sh", constraint.params["path"]
    end

    test "does not allow adding 'all repos' for second time" do
      create(:policy_group_membership, policy_group: @policy_group, target: @org)
      create(:policy_constraint, policy_group: @policy_group, params: @params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)

      policy_group_2 = create(:policy_group, :all_targets, owner: @org, name: "all repo 2")

      constraint = Codespaces::PolicyConstraint.new(
        policy_group: policy_group_2,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: @params
      )

      assert_equal 1, Codespaces::PolicyGroupMembership.joins(:policy_constraints).length
      refute constraint.valid?
      assert_equal constraint.errors[:host_setup].first, "can only be added once for 'All repositories' policy target"
    end

    test "allows adding 'all repo' with existing selected repos" do
      policy_group_repo = create(:policy_group, :selected_targets, targets: [@org_repo], owner: @org, name: "specific repo")
      create(:policy_constraint, policy_group: policy_group_repo, params: @params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)

      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: @params
      )

      assert_equal 1, Codespaces::PolicyGroupMembership.joins(:policy_constraints).length
      assert constraint.valid?
      refute_nil constraint.params

      assert_equal @org_repo.name_with_owner, constraint.params["repo"]
      assert_equal "main", constraint.params["branch"]
      assert_equal "host-setup.sh", constraint.params["path"]
    end

    test "allows adding 'selected repos' for the first time" do
      policy_group_repo = create(:policy_group, :selected_targets, targets: [@org_repo], owner: @org, name: "specific repo")

      constraint = Codespaces::PolicyConstraint.new(
        policy_group: policy_group_repo,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: @params
      )

      assert_equal 0, Codespaces::PolicyGroupMembership.joins(:policy_constraints).length
      assert constraint.valid?
      refute_nil constraint.params

      assert_equal @org_repo.name_with_owner, constraint.params["repo"]
      assert_equal "main", constraint.params["branch"]
      assert_equal "host-setup.sh", constraint.params["path"]
    end

    test "allows updating existing 'selected repos' policy" do
      policy_group_repo = create(:policy_group, :selected_targets, targets: [@org_repo], owner: @org, name: "specific repo")
      create(:policy_constraint, policy_group: policy_group_repo, params: @params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)

      repo_2 = create(:private_repository, owner: @org)
      params_updated = {
        repo: repo_2.name_with_owner,
        branch: "main",
        path: "host-setup-2.sh"
      }

      policy_group_repo.apply_constraints!([{ name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP, value: params_updated.to_json }])
      assert_equal 1, policy_group_repo.policy_constraints.count

      constraint = policy_group_repo.policy_constraints.first
      assert_equal Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP, constraint.name
      assert_equal repo_2.name_with_owner, constraint.params["repo"]
      assert_equal "main", constraint.params["branch"]
      assert_equal "host-setup-2.sh", constraint.params["path"]
    end

    test "allows adding 'selected repos' for the first time - cross org" do
      org_new = create(:organization)
      repo_new = create(:private_repository, owner: org_new)
      policy_group_new = create(:policy_group, :selected_targets, targets: [repo_new], owner: org_new)

      params_new = {
        repo: repo_new.name_with_owner,
        branch: "main",
        path: "host-setup.sh"
      }

      create(:policy_constraint, policy_group: policy_group_new, params: params_new, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)

      policy_group_repo = create(:policy_group, :selected_targets, targets: [@org_repo], owner: @org, name: "specific repo")

      constraint = Codespaces::PolicyConstraint.new(
        policy_group: policy_group_repo,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: @params
      )

      assert_equal 1, Codespaces::PolicyGroupMembership.joins(:policy_constraints).length
      assert constraint.valid?
      refute_nil constraint.params

      assert_equal @org_repo.name_with_owner, constraint.params["repo"]
      assert_equal "main", constraint.params["branch"]
      assert_equal "host-setup.sh", constraint.params["path"]
    end

    test "allows adding 'selected repos' for the first time - cross org (2)" do
      org_new = create(:organization)
      repo_new = create(:private_repository, owner: org_new)
      policy_group_new = create(:policy_group, :all_targets, owner: org_new)

      params_new = {
        repo: repo_new.name_with_owner,
        branch: "main",
        path: "host-setup.sh"
      }

      create(:policy_constraint, policy_group: policy_group_new, params: params_new, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)

      policy_group_repo = create(:policy_group, :selected_targets, targets: [@org_repo], owner: @org, name: "specific repo")

      constraint = Codespaces::PolicyConstraint.new(
        policy_group: policy_group_repo,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: @params
      )

      assert_equal 1, Codespaces::PolicyGroupMembership.joins(:policy_constraints).length
      assert constraint.valid?
      refute_nil constraint.params

      assert_equal @org_repo.name_with_owner, constraint.params["repo"]
      assert_equal "main", constraint.params["branch"]
      assert_equal "host-setup.sh", constraint.params["path"]
    end

    test "does not allow adding 'selected repos' for the second time" do
      policy_group_repo = create(:policy_group, :selected_targets, targets: [@org_repo], owner: @org, name: "specific repo")
      create(:policy_constraint, policy_group: policy_group_repo, params: @params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)

      policy_group_repo_2 = create(:policy_group, :selected_targets, targets: [@org_repo], owner: @org, name: "specific repo 2")

      constraint = Codespaces::PolicyConstraint.new(
        policy_group: policy_group_repo_2,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: @params
      )

      assert_equal 1, Codespaces::PolicyGroupMembership.joins(:policy_constraints).length

      refute constraint.valid?
      assert_equal constraint.errors[:host_setup].first, "can only be added once per repository"
    end

    test "allows adding 'selected repos' for the second time " do
      policy_group_repo = create(:policy_group, :selected_targets, targets: [@org_repo], owner: @org, name: "specific repo")
      create(:policy_constraint, policy_group: policy_group_repo, params: @params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)

      repo_new = create(:private_repository, owner: @org)
      policy_group_repo_2 = create(:policy_group, :selected_targets, targets: [repo_new], owner: @org, name: "specific repo 2")

      constraint = Codespaces::PolicyConstraint.new(
        policy_group: policy_group_repo_2,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params: @params
      )

      assert_equal 1, Codespaces::PolicyGroupMembership.joins(:policy_constraints).length

      assert constraint.valid?
      assert_equal @org_repo.name_with_owner, constraint.params["repo"]
      assert_equal "main", constraint.params["branch"]
      assert_equal "host-setup.sh", constraint.params["path"]
    end

    test "allows adding 'selected repos' with all repos" do
      org = create(:organization)
      policy_group = create(:policy_group, :all_targets, owner: org)
      repo_new = create(:private_repository, owner: org)
      params = @params.merge(repo: repo_new.name_with_owner)

      create(:policy_constraint, policy_group: policy_group, params:, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)
      policy_group_selected_repo = create(:policy_group, :selected_targets, targets: [repo_new],  owner: org, name: "specific repo")

      constraint = Codespaces::PolicyConstraint.new(
        policy_group: policy_group_selected_repo,
        name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP,
        params:
      )

      assert_equal 1, Codespaces::PolicyGroupMembership.joins(:policy_constraints).length

      assert constraint.valid?, constraint.errors.full_messages.join(", ")
      refute_nil constraint.params

      assert_equal repo_new.name_with_owner, constraint.params["repo"]
      assert_equal "main", constraint.params["branch"]
      assert_equal "host-setup.sh", constraint.params["path"]
    end
  end

  context "specific constraints" do
    test "codespaces.allowed_machine_types" do
      assert_nothing_raised do
        constraint = Codespaces::PolicyConstraint.create!(
          policy_group: @policy_group,
          name: "codespaces.allowed_machine_types",
          allowed_values: ["basicLinux32gb"]
        )
      end
    end

    test "codespaces.allowed_port_privacy_settings" do
      assert_nothing_raised do
        constraint = Codespaces::PolicyConstraint.create!(
          policy_group: @policy_group,
          name: "codespaces.allowed_port_privacy_settings",
          allowed_values: ["org"]
        )
      end
    end

    test "codespaces.allowed_entities" do
      assert_nothing_raised do
        constraint = Codespaces::PolicyConstraint.create!(
          policy_group: @policy_group,
          name: "codespaces.allowed_entities",
          allowed_values: ["selected"]
        )
      end
    end

    test "codespaces.allowed_entities is not valid if trying to pass in more than one value" do
      constraint = Codespaces::PolicyConstraint.create(
        policy_group: @policy_group,
        name: "codespaces.allowed_entities",
        allowed_values: %w[selected none]
      )
      refute constraint.valid?
    end

    test "codespaces.allowed_entities is not valid if trying to pass in bad value value" do
      constraint = Codespaces::PolicyConstraint.create(
        policy_group: @policy_group,
        name: "codespaces.allowed_entities",
        allowed_values: ["badvalue"]
      )
      refute constraint.valid?
    end

    test "codespaces.allowed_entities cannot have more than two" do
      constraint1 = Codespaces::PolicyConstraint.create(
        policy_group: @policy_group,
        name: "codespaces.allowed_entities",
        allowed_values: ["selected"]
      )
      constraint2 = Codespaces::PolicyConstraint.create(
        policy_group: @policy_group,
        name: "codespaces.allowed_entities",
        allowed_values: ["all"]
      )
      assert constraint1.valid?
      refute constraint2.valid?
    end
  end

  context "ddog instrumentation" do
    test "machine type policy: instruments on create" do
      constraint = Codespaces::PolicyConstraint.create!(
        policy_group: @policy_group,
        name: "codespaces.allowed_machine_types",
        allowed_values: ["basicLinux32gb"]
      )
      assert_dogstats_increment(1, "codespaces.policy_constraint.created", tags: ["constraint_name:codespaces.allowed_machine_types"])
    end

    test "machine type policy: instruments on destroy" do
      constraint = Codespaces::PolicyConstraint.create!(
        policy_group: @policy_group,
        name: "codespaces.allowed_machine_types",
        allowed_values: ["basicLinux32gb"]
      )
      constraint.destroy!
      assert_dogstats_increment(1, "codespaces.policy_constraint.destroyed", tags: ["constraint_name:codespaces.allowed_machine_types"])
    end

    test "port privacy policy: instruments on create" do
      constraint = Codespaces::PolicyConstraint.create!(
        policy_group: @policy_group,
        name: "codespaces.allowed_port_privacy_settings",
        allowed_values: ["org"]
      )
      assert_dogstats_increment(1, "codespaces.policy_constraint.created", tags: ["constraint_name:codespaces.allowed_port_privacy_settings"])
    end

    test "port privacy policy: instruments on destroy" do
      constraint = Codespaces::PolicyConstraint.create!(
        policy_group: @policy_group,
        name: "codespaces.allowed_port_privacy_settings",
        allowed_values: ["org"]
      )
      constraint.destroy!
      assert_dogstats_increment(1, "codespaces.policy_constraint.destroyed", tags: ["constraint_name:codespaces.allowed_port_privacy_settings"])
    end
  end

  context "#display_value" do
    test "shows skus if the user is FFed into the sku" do
      enable_feature_flag(:codespaces_linux_x_large, @policy_group.owner)
      constraint = Codespaces::PolicyConstraint.new(
        policy_group: @policy_group,
        name: "codespaces.allowed_machine_types",
        allowed_values: %w[premiumLinux largePremiumLinux xLargePremiumLinux],
      )
      assert_equal "8-core, 16-core, 32-core", constraint.display_value
    end
  end
end
