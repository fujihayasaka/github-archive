# typed: true
# frozen_string_literal: true

require "test_helper"

module Permissions
  class FineGrainedPermissionImTest < GitHub::TestCase
    context "validations" do
      test "action is required" do
        assert_raises_with_message(ArgumentError, "Action can't be blank") do
          fgp = FineGrainedPermissionIm.new("", target_type: "Repository")
        end
      end

      test "valid target type is required" do
        assert_raises_with_message(ArgumentError, "Invalid target type") do
          fgp = FineGrainedPermissionIm.new("my_action", target_type: "RandomTargetType")
        end
      end

      test "all actions are unique" do
        duplicate_actions = []
        FineGrainedPermissionIm.all.group_by(&:action).each do |action, fgps|
          if fgps.size > 1
            duplicate_actions << action
          end
        end
        assert duplicate_actions.empty?, "Duplicate actions registered with Permissions::FineGrainedPermissionIm: #{duplicate_actions.join(", ")}"
      end
    end

    context "oauth_scopes" do
      test "loads oauth scopes if provided" do
        fgp = FineGrainedPermissionIm.find!(:enterprise_test_read_permission)
        assert_equal ["repo", "admin:enterprise"], fgp.oauth_scopes
      end

      test "returns empty array if no oauth scopes" do
        fgp = FineGrainedPermissionIm.find!(:admin_repo)
        assert_empty fgp.oauth_scopes
      end
    end

    context "programmatic_access" do
      test "loads programmatic access if provided" do
        owner = create :user
        non_member = create :user
        biz = create :business, owners: [owner]

        fgp = FineGrainedPermissionIm.find!(:enterprise_test_read_permission)

        assert fgp.supports_programmatic_access?
        assert_equal "enterprise_administration", fgp.programmatic_resource
        assert_equal "read", fgp.programmatic_action

        # owner and non_member are not a programmatic actors
        # the important thing here is to verify we are calling a method that exists and gives a result
        # (and its much easier to set up a test with a User actor)
        assert fgp.programmatic_access_check_for(biz).call(owner)
        refute fgp.programmatic_access_check_for(biz).call(non_member)
      end

      test "handles FGP without programmatic access setup" do
        repo = create :repository
        user = create :user
        fgp = FineGrainedPermissionIm.find!(:admin_repo) # any FGP without programmatic access setup will work
        refute fgp.supports_programmatic_access?
        assert_nil fgp.programmatic_resource
        assert_nil fgp.programmatic_action

        assert_raises_with_message(FineGrainedPermissionIm::ProgrammaticAccessNotConfiguredError, "programmatic access is not configured for the 'admin_repo' FGP") do
          # this is not a programmatic actor, but it doesn't matter for checking the error
          fgp.programmatic_access_check_for(repo).call(user)
        end
      end
    end

    context "self.all" do
      test "returns all fine grained permissions" do
        fgps = FineGrainedPermissionIm.all
        private_fgps = FineGrainedPermissionIm.send(:system_fgps).values
        assert_equal private_fgps.count, fgps.count
        fgps.each do |fgp|
          private_fgp = private_fgps.find { |pfgp| pfgp.action == fgp.action }
          refute_nil private_fgp
        end
      end
    end

    context "self.where" do
      test "filters by action" do
        fgps = FineGrainedPermissionIm.where(actions: :add_label)

        assert_equal 1, fgps.count
        assert_equal "add_label", fgps.first&.action
      end

      test "filters by custom_roles_enabled" do
        fgps = FineGrainedPermissionIm.where(custom_roles_enabled: true)
        refute_empty fgps
        assert fgps.all?(&:custom_roles_enabled)

        fgps = FineGrainedPermissionIm.where(custom_roles_enabled: false)
        refute_empty fgps
        assert fgps.none?(&:custom_roles_enabled)
      end

      test "filters by target_type" do
        org_fgps = FineGrainedPermissionIm.where(target_type: "Organization")
        refute_empty org_fgps
        assert org_fgps.all? { |fgp| fgp.target_type == "Organization" }

        repo_fgps = FineGrainedPermissionIm.where(target_type: "Repository")
        refute_empty repo_fgps
        assert repo_fgps.all? { |fgp| fgp.target_type == "Repository" }

        biz_fgps = FineGrainedPermissionIm.where(target_type: "Business")
        refute_empty biz_fgps
        assert biz_fgps.all? { |fgp| fgp.target_type == "Business" }
      end

      test "raises ArgumentError if invalid target_type is passed in" do
        assert_raises_with_message(ArgumentError, "Invalid target type") do
          FineGrainedPermissionIm.where(target_type: "RandomTargetType")
        end
      end

      test "filters by multiple conditions" do
        fgps = FineGrainedPermissionIm.where(
          target_type: "Organization",
          custom_roles_enabled: true,
          actions: [
            :read_audit_logs, # should match
            :view_security_managers, # not for custom roles
            :add_label, # repo permission
          ]
        )
        assert_equal 1, fgps.count
        assert_equal "read_audit_logs", fgps.first&.action
      end

      test "preserves ordering of provided actions" do
        close_first = FineGrainedPermissionIm.where(actions: [:close_issue, :delete_issue])
        delete_first = FineGrainedPermissionIm.where(actions: [:delete_issue, :close_issue])

        assert_equal "close_issue", close_first.first&.action
        assert_equal "delete_issue", delete_first.first&.action
      end

      test "returns everything if passed no arguments" do
        assert_same_elements FineGrainedPermissionIm.all, FineGrainedPermissionIm.where
      end
    end

    context "self.find" do
      test "returns FGP by symbol" do
        fgp = FineGrainedPermissionIm.find(:add_label)
        refute_nil fgp
        assert_equal "add_label", T.must(fgp).action
      end

      test "returns FGP by string" do
        fgp = FineGrainedPermissionIm.find("add_label")
        refute_nil fgp
        assert_equal "add_label", T.must(fgp).action
      end

      test "returns nil if no FGP" do
        fgp = FineGrainedPermissionIm.find(:does_not_exist)
        assert_nil fgp
      end
    end

    context "self.find!" do
      test "returned FGPs are non-modifiable" do
        fgp = FineGrainedPermissionIm.find!(:add_label)

        assert_raises(FrozenError) { fgp.instance_variable_set(:@action, "we broke it!") }
        assert_equal "add_label", fgp.action
      end

      test "raises an error if no FGP" do
        assert_raises_with_message(FineGrainedPermissionIm::PermissionNotFoundError, "No permission with the action 'does_not_exist' exists.") do
          FineGrainedPermissionIm.find!(:does_not_exist)
        end
      end
    end

    context "self.disabled_fgps" do
      test "disabling feature flag disables FGP for org" do
        org = create(:organization, business: create(:business))
        GitHub.flipper[:api_insights_org_viewer_fgp].disable
        assert_includes FineGrainedPermissionIm.disabled_fgps(org), :view_org_api_insights
      end

      test "enabling feature flag enables FGP for org" do
        org = create(:organization, business: create(:business))
        GitHub.flipper[:api_insights_org_viewer_fgp].enable
        refute_includes FineGrainedPermissionIm.disabled_fgps(org), :view_org_api_insights
      end

      test "disabling feature flag disables FGP for business" do
        business = create(:business)
        GitHub.flipper[:actions_network_configuration_api].disable
        assert_includes FineGrainedPermissionIm.disabled_fgps(business), :read_organization_network_configurations
      end

      test "enabling feature flag enables FGP for business" do
        business = create(:business)
        GitHub.flipper[:actions_network_configuration_api].enable
        refute_includes FineGrainedPermissionIm.disabled_fgps(business), :read_organization_network_configurations
      end

      test "disabling feature flag disables FGP for business owned org roles" do
        business = create(:business)
        GitHub.flipper[:api_insights_org_viewer_fgp].disable
        assert_includes FineGrainedPermissionIm.disabled_fgps(business, target_type: "Organization"), :view_org_api_insights
      end

      test "enabling feature flag enables FGP for business owned org roles" do
        business = create(:business)
        GitHub.flipper[:api_insights_org_viewer_fgp].enable
        refute_includes FineGrainedPermissionIm.disabled_fgps(business, target_type: "Organization"), :view_org_api_insights
      end
    end
  end
end
