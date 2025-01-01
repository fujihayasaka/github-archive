# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomOrganizationRoleTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper
  include HydroTestHelpers

  setup do
    if GitHub.enterprise?
      GitHub::Plan.stubs(:business_plus).raises(StandardError.new("No plan found for business_plus"))
    end
  end

  fixtures do
    @org = create(:business_plus_organization, login: "github")
    @business = create(:business)
  end

  context "validations" do
    test "organization cannot create more than the limit of custom roles for business_plus plans" do
      org = create(:business_plus_organization)

      OrganizationRole::BUSINESS_PLUS_CUSTOM_ORG_ROLE_LIMIT.times do
        create(:custom_organization_role, owner_id: org.id, owner_type: "Organization")
      end
      assert_equal OrganizationRole::BUSINESS_PLUS_CUSTOM_ORG_ROLE_LIMIT, OrganizationRole.custom_roles_for_org(org).count

      error = assert_raises ActiveRecord::RecordInvalid do
        create(:custom_organization_role, owner_id: org.id, owner_type: "Organization")
      end
      assert_match (/Owner is already at the maximum number of custom roles/), error.message
    end

    test "enterprise cannot create more than the limit of custom roles", skip_if_feature_disabled: :enterprise_custom_organization_roles do
      org = create(:business_plus_organization)
      org.business = GitHub.single_business_environment? ? GitHub.global_business : create(:business)

      OrganizationRole::BUSINESS_PLUS_CUSTOM_ORG_ROLE_LIMIT.times do
        create(:custom_organization_role, owner: org.business)
      end

      error = assert_raises ActiveRecord::RecordInvalid do
        create(:custom_organization_role, owner: org.business)
      end
      assert_match (/Owner is already at the maximum number of custom roles/), error.message
    end

    test "org roles can have a system_repository base role" do
      org = create(:business_plus_organization)
      role = assert_nothing_raised do
        OrganizationRole.create!({
          name: "all repo role",
          owner_id: org.id,
          owner_type: "Organization",
          base_role_id: Role.admin_role.id
        })
      end
      assert_equal Role.admin_role, role.base_role
    end

    test "org roles can have no base role" do
      org = create(:business_plus_organization)
      role = assert_nothing_raised do
        OrganizationRole.create!({
          name: "org role",
          owner_id: org.id,
          owner_type: "Organization",
          base_role_id: nil
        })
      end
      assert_nil role.base_role
    end

    test "org roles cannot have a non-system_repository role as a base role" do
      org = create(:business_plus_organization)
      repo_role = create(:role, owner_id: org.id, owner_type: "Organization")

      error = assert_raises ActiveRecord::RecordInvalid do
        OrganizationRole.create!({
          name: "org role",
          owner_id: org.id,
          owner_type: "Organization",
          base_role_id: repo_role.id
        })
      end

      assert_match (/Base role must be one of: read, triage, write, maintain, admin/), error.message
    end

    test "org roles cannot have a base role that doesn't exist" do
      org = create(:business_plus_organization)
      highest_role_id = Role.maximum(:id)

      error = assert_raises ActiveRecord::RecordInvalid do
        OrganizationRole.create!({
          name: "org role",
          owner_id: org.id,
          owner_type: "Organization",
          base_role_id: highest_role_id + 1
        })
      end

      assert_match (/Base role must be one of: read, triage, write, maintain, admin/), error.message
    end

    test "enterprise can't create org role", skip_if_feature_enabled: :enterprise_custom_organization_roles do
      org = create(:business_plus_organization)
      org.business = GitHub.single_business_environment? && GitHub.global_business ? GitHub.global_business : create(:business)

      error = assert_raises ActiveRecord::RecordInvalid do
        OrganizationRole.create!({
          name: "enterprise role",
          owner_id: org.business.id,
          owner_type: "Business"
        })
      end

      assert_match (/Owner Enterprises cannot create Custom Roles/), error.message
    end
  end

  context "organization roles comparison and ranking" do
    test "org roles are ranked correctly" do
      org = create(:business_plus_organization)
      high_role = assert_nothing_raised do
        OrganizationRole.create!({
          name: "all repo role admin",
          owner_id: org.id,
          owner_type: "Organization",
          base_role_id: Role.admin_role.id
        })
      end
      low_role = assert_nothing_raised do
        OrganizationRole.create!({
          name: "all repo role read",
          owner_id: org.id,
          owner_type: "Organization",
          base_role_id: Role.read_role.id
        })
      end
      assert_equal Role.admin_role, high_role.base_role
      assert_equal Role.read_role, low_role.base_role
      assert_equal true, high_role.target_greater_than_other_role?(other_role: "read")
      assert_equal false, low_role.target_greater_than_other_role?(other_role: "admin")
      assert_equal true, high_role.target_greater_than_or_equal_to_other_role?(other_role: "read")
      assert_equal true, low_role.target_greater_than_or_equal_to_other_role?(other_role: "read")
      assert_equal false, low_role.target_greater_than_or_equal_to_other_role?(other_role: "write")
    end

    test "only org roles with base roles can be compared" do
      org = create(:business_plus_organization)
      high_role = assert_nothing_raised do
        OrganizationRole.create!({
          name: "regular org role",
          owner_id: org.id,
          owner_type: "Organization",
          base_role_id: nil
        })
      end

      error = assert_raises RuntimeError do
        high_role.target_greater_than_other_role?(other_role: "read")
      end

      assert_equal "No base role available to compare.", error.message
    end
  end

  context "retrieving custom roles" do
    test ".custom_roles_for_org returns only custom org roles for an org" do
      org = create(:business_plus_organization)
      other_org = create(:business_plus_organization)
      custom_role = create(:custom_organization_role, owner_id: org.id, owner_type: "Organization")
      create_custom_role(owner: org)

      create(:custom_organization_role, owner_id: other_org.id, owner_type: "Organization")

      roles = OrganizationRole.custom_roles_for_org(org)
      assert_equal 1, roles.count
      assert_equal roles.first, custom_role
    end

    test ".custom_role_by_name can only retrieve org roles" do
      org = create(:business_plus_organization)
      custom_org_role = create(:custom_organization_role, owner_id: org.id, owner_type: "Organization")
      custom_repo_role = create_custom_role(owner: org)

      org_role = OrganizationRole.custom_role_by_name(custom_org_role.name, owner: org)
      repo_role = OrganizationRole.custom_role_by_name(custom_repo_role.name, owner: org)

      assert_equal custom_org_role, org_role
      assert_nil repo_role
    end
  end

  context ".custom_org_role_limit_for" do
    if GitHub.billing_enabled?
      test "business plus plan custom role limit" do
        assert_equal OrganizationRole::BUSINESS_PLUS_CUSTOM_ORG_ROLE_LIMIT, OrganizationRole.custom_role_limit_for_owner(create(:business_plus_organization))
      end

      test "business plan custom role limit" do
        assert_equal 0, OrganizationRole.custom_role_limit_for_owner(create(:organization, plan: "business"))
      end

      test "free plan custom role limit" do
        assert_equal 0, OrganizationRole.custom_role_limit_for_owner(create(:organization, plan: "free"))
      end

      test "legacy plan custom role limit" do
        assert_equal 0, OrganizationRole.custom_role_limit_for_owner(create(:organization, plan: "bronze"))
      end

      test "enterprise custom role limit" do
        business = create(:business)
        assert_equal "business_plus", business.plan.to_s
        assert_equal 10, OrganizationRole.custom_role_limit_for_owner(business)
      end

      test "enterprise free plan custom role limit" do
        business = create(:business)
        business.downgrade_to_free_plan
        assert_equal 0, OrganizationRole.custom_role_limit_for_owner(business)
      end
    end

    if GitHub.enterprise?
      test "enterprise custom role limit" do
        assert OrganizationRole::ENTERPRISE_CUSTOM_ORG_ROLE_LIMIT, OrganizationRole.custom_role_limit_for_owner(create(:organization))
      end
    end
  end

  context ".assignments_for" do
    test "returns all assignments of a team" do
      org_role_1 = create(:custom_organization_role, owner_id: @org.id, owner_type: "Organization")
      org_role_2 = create(:custom_organization_role, owner_id: @org.id, owner_type: "Organization")
      parent_team = create :team, privacy: :closed, organization: @org
      child_team = create :team, privacy: :closed, parent_team_id: parent_team.id, organization: @org
      @org.grant_org_role(assignee: parent_team, role: org_role_1)
      @org.grant_org_role(assignee: child_team, role: org_role_2)

      roles = OrganizationRole.assignments_for(actor: parent_team, org: @org)
      assert_equal 1, roles.count
      assert_equal org_role_1, roles.first

      roles = OrganizationRole.assignments_for(actor: child_team, org: @org)
      assert_equal 2, roles.count
      assert_same_elements [org_role_1, org_role_2], roles
    end

    test "returns only direct assignments of a user" do
      org_role_1 = create(:custom_organization_role, owner_id: @org.id, owner_type: "Organization")
      org_role_2 = create(:custom_organization_role, owner_id: @org.id, owner_type: "Organization")
      team = create :team, privacy: :closed, organization: @org
      member = create(:user, login: "org-member")
      @org.add_member(member)
      team.add_member(member)

      @org.grant_org_role(assignee: member, role: org_role_1)
      @org.grant_org_role(assignee: team, role: org_role_2)

      roles = OrganizationRole.assignments_for(actor: member, org: @org)
      assert_equal 1, roles.count
      assert_same_elements [org_role_1], roles
    end

    test "returns an error for other targets than user or teams" do
      assert_raises TypeError do
        OrganizationRole.assignments_for(actor: create(:repository), org: create(:organization))
      end
    end
  end

  context ".repository_roles_for" do
    test "returns all roles a user has across repositories" do
      member = create(:user, login: "org-member")
      repo_1 = create(:repository, owner: @org)
      repo_2 = create(:repository, owner: @org)
      user_role_1 = create(:user_role, actor: member, role: Role.maintain_role, target: repo_1)
      user_role_2 = create(:user_role, actor: member, role: Role.triage_role, target: repo_2)
      user_role_3 = OrganizationRole.all_repo_write_role # should not be included, not repo role

      roles = OrganizationRole.repository_roles_for(actor: member, org: @org)
      assert_equal 2, roles.count
      assert_same_elements [user_role_1.role, user_role_2.role], roles
    end

    test "returns all roles a team has across repositories" do
      team = create :team, privacy: :closed, organization: @org
      repo_1 = create(:repository, owner: @org)
      repo_2 = create(:repository, owner: @org)
      role_1 = create(:user_role, actor: team, role: Role.maintain_role, target: repo_1)
      role_2 = create(:user_role, actor: team, role: Role.triage_role, target: repo_2)
      role_3 = OrganizationRole.all_repo_write_role # should not be included, not repo role

      roles = OrganizationRole.repository_roles_for(actor: team, org: @org)
      assert_equal 2, roles.count
      assert_same_elements [role_1.role, role_2.role], roles
    end
  end

  context "audit log events" do
    test "create custom org role with no fgps has correct audit log payload" do
      events = subscribe "organization_role.create"
      custom_role = create_custom_org_role(role_name: "developer", owner: @org)

      expected_payload = {
        name: "developer",
        owner: "github",
        role_permissions: "None",
        base_role: nil,
        business: @org.business,
        org: @org.login,
        org_id: @org.id,
      }

      # Verifying the full shape of the audit log payload.
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "create custom org role with fgps has correct audit log payload" do
      events = subscribe "organization_role.create"

      # We can't use the test helper because it creates a bare Role without FGPs and saves it, causing
      # the instrumentation to fire. Instead we do it here like we do in production

      fgps = %w[manage_organization_webhooks read_audit_logs]
      custom_role = OrganizationRole.new(
        owner_id: @org.id,
        owner_type: "Organization",
        name: "developer",
      )

      Permissions::CustomRoles.create!(custom_role, fgps: fgps)

      expected_payload = {
        name: "developer",
        owner: "github",
        role_permissions: "Manage organization webhooks and View organization audit log",
        base_role: nil,
        business: @org.business,
        org: @org.login,
        org_id: @org.id,
      }

      # Verifying the full shape of the audit log payload.
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "destroy org role generates audit log entry" do
      events = subscribe "organization_role.destroy"
      custom_role = create_custom_org_role(role_name: "developer", owner: @org)
      custom_role.destroy

      expected_payload = {
        name: "developer",
        owner: "github",
        role_permissions: "None",
        base_role: nil,
        business: @org.business,
        org: @org.login,
        org_id: @org.id,
      }

      # Verifying the full shape of the audit log payload.
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "update org role generates audit log entry" do
      events = subscribe "organization_role.update"

      custom_role = create_custom_org_role(role_name: "developer", owner: @org)
      custom_role.update! name: "intern"

      expected_payload = {
        name: "intern",
        owner: "github",
        role_permissions: "None",
        base_role: nil,
        business: @org.business,
        org: @org.login,
        org_id: @org.id,
        changes: {
          old_name: "developer",
        },
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context "system roles" do
    test "all-repo system roles exist" do
      [
        [OrganizationRole.all_repo_read_role, Role.read_role],
        [OrganizationRole.all_repo_triage_role, Role.triage_role],
        [OrganizationRole.all_repo_write_role, Role.write_role],
        [OrganizationRole.all_repo_maintain_role, Role.maintain_role],
        [OrganizationRole.all_repo_admin_role, Role.admin_role]
      ].each do |all_repo_role, single_repo_role|
        refute_nil all_repo_role
        assert_nil all_repo_role.owner_id
        assert_nil all_repo_role.owner_type
        assert_equal single_repo_role.id, all_repo_role.base_role_id
        assert_equal 0, all_repo_role.permissions.count
      end
    end
  end

  context "org role query" do
    context "parse string" do
      %w[
       role
       is
      ].each do |value|
        test "parses a string with single filter #{value}" do
          hash = OrganizationRole.parse_query("#{value}:developer")
          assert hash[value.to_sym]
          assert_equal "developer", hash[value.to_sym]
        end

        test "parses a string with multiple filter #{value}" do
          # only return the most right role
          hash = OrganizationRole.parse_query("#{value}:developer #{value}:designer")
          assert hash[value.to_sym]
          assert_equal "designer", hash[value.to_sym]
        end

        test "parse with query and filter #{value}" do
          hash = OrganizationRole.parse_query("#{value}:developer foo bar")
          assert hash[value.to_sym]
          assert_equal "developer", hash[value.to_sym]
          assert_equal "foo bar", hash[:query]
        end
      end

      test "handle invalid filter values" do
        hash = OrganizationRole.parse_query("test:developer foo bar")
        refute hash[:test]
        assert_equal "test:developer foo bar", hash[:query]
      end
    end

    context "parse hash" do
      %w[
        role
        is
       ].each do |value|
         test "stringify a hash with single filter #{value}" do
           hash = { value.to_sym => "developer" }
           query_string = OrganizationRole.stringify_query_hash(hash)
           assert_equal "#{value}:developer", query_string
         end

         test "stringify with query and filter #{value}" do
           hash = { value.to_sym => "developer", :query => "foo bar" }
           query_string = OrganizationRole.stringify_query_hash(hash)
           assert_equal "#{value}:developer foo bar", query_string
         end
       end

      test "omit invalid filter values" do
        hash = { foobar: "developer", query: "foo bar" }
        query_string = OrganizationRole.stringify_query_hash(hash)
        assert_equal "foo bar", query_string
      end
    end
  end

  context ".visible_preset_roles" do
    test "visible_preset_roles returns org system roles for org" do
      roles = %w(all_repo_read all_repo_triage all_repo_write all_repo_maintain all_repo_admin ci_cd_admin security_manager)
      assert_same_elements roles, OrganizationRole.visible_preset_roles(@org).map(&:name)
    end

    test "does not return custom role with name matching system role" do
      create_custom_org_role(role_name: "all_repo_read", owner: @org)

      expected_roles = [
        OrganizationRole.all_repo_read_role,
        OrganizationRole.all_repo_triage_role,
        OrganizationRole.all_repo_write_role,
        OrganizationRole.all_repo_maintain_role,
        OrganizationRole.all_repo_admin_role,
        OrganizationRole.ci_cd_admin_role,
        OrganizationRole.security_manager_role,
      ]

      assert_same_elements expected_roles, OrganizationRole.visible_preset_roles(@org)
    end

    test "visible_preset_roles returns org system roles for business" do
      roles = %w(all_repo_read all_repo_triage all_repo_write all_repo_maintain all_repo_admin ci_cd_admin security_manager)
      assert_same_elements roles, OrganizationRole.visible_preset_roles(@business).map(&:name)
    end

    test "does not return system roles for app management" do
      roles = OrganizationRole.visible_preset_roles(@org).map(&:name)

      refute_includes roles, "app_manager"
      refute_includes roles, "app_owner"
    end
  end

  context ".visible_roles" do
    test "visible_roles returns org system roles and custom roles sorted" do
      pre_defined_roles = %w(all_repo_read all_repo_write all_repo_triage all_repo_maintain all_repo_admin ci_cd_admin security_manager)
      custom_org_role = create_custom_org_role(role_name: "developer", owner: @org)
      assert_equal(pre_defined_roles + [custom_org_role.name], OrganizationRole.visible_roles(@org).map(&:name))
    end

    test "includes enterprise-owned roles for an organization", skip_if_feature_disabled: :enterprise_custom_organization_roles do
      org = create(:business_plus_organization)
      org.business = GitHub.single_business_environment? ? GitHub.global_business : create(:business)
      custom_org_role = create(:custom_organization_role, owner: org.business)

      assert_includes OrganizationRole.visible_roles(org), custom_org_role
    end

    test "excludes enterprise-owned roles for an organization", skip_if_feature_enabled: :enterprise_custom_organization_roles do
      org = create(:business_plus_organization)
      org.business = GitHub.single_business_environment? ? GitHub.global_business : create(:business)

      enable_feature_flag(:enterprise_custom_organization_roles)
      custom_org_role = create(:custom_organization_role, owner: org.business)
      assert_includes OrganizationRole.custom_roles_for_owner(org.business), custom_org_role
      disable_feature_flag(:enterprise_custom_organization_roles)
      disable_feature_flag(:enterprise_custom_organization_roles, org.business)

      refute_includes OrganizationRole.visible_roles(org), custom_org_role
    end
  end

  context ".sorted_visible_preset_roles" do
    test "sort all repo roles in a specific way, and other system roles and custom roles by display_name" do
      all_repo_roles = OrganizationRole.where(name: %w(all_repo_read all_repo_triage all_repo_write all_repo_maintain all_repo_admin ci_cd_admin))
      new_org_system_role = build(:role, :preset, name: "a_new_system_role")
      OrganizationRole.stubs(:visible_preset_roles).returns(all_repo_roles + [new_org_system_role])
      assert_equal %w(all_repo_read all_repo_write all_repo_triage all_repo_maintain all_repo_admin ci_cd_admin a_new_system_role), OrganizationRole.sorted_visible_preset_roles(@org).map(&:name)
    end
  end

  context " .org_roles_with_repo_access" do
    test "return all org roles with an associated base role" do
      roles = %w(all_repo_read all_repo_write all_repo_triage all_repo_maintain all_repo_admin security_manager)
      all_repo_roles = OrganizationRole.where(name: roles)
      new_org_role = create(:custom_organization_role, name: "a_new_role", owner_id: @org.id, owner_type: "Organization", target_type: "Organization")
      new_org_role_with_base_role = create(:custom_organization_role, name: "new_role_with_base_role", base_role: Role.read_role, owner_id: @org.id, owner_type: "Organization",  target_type: "Organization")
      assert_equal roles + %w(new_role_with_base_role), OrganizationRole.org_roles_with_repo_access(@org).map(&:name)
    end
  end

  context "#display_name" do
    test "fetches display name from SYSTEM_ROLE_METADATA if present" do
      assert_equal "All-repository read", OrganizationRole.all_repo_read_role.display_name
      assert_equal "all_repo_read", OrganizationRole.all_repo_read_role.name
    end
  end

  context "#description" do
    test "returns description from SYSTEM_ROLE_METADATA if present" do
      assert_equal OrganizationRole::SYSTEM_ROLE_METADATA.dig(:all_repo_read, :description), OrganizationRole.all_repo_read_role.description
    end

    test "does not return description from SYSTEM_ROLE_METADATA if custom role" do
      description = "This is a custom role"
      custom_role = create_custom_org_role(owner: @org, role_name: "all_repo_read", role_description: description)
      assert_equal description, custom_role.description
    end
  end

  context "#octicon" do
    test "returns octicon from SYSTEM_ROLE_METADATA if present" do
      assert_equal OrganizationRole::SYSTEM_ROLE_METADATA.dig(:all_repo_read, :octicon), OrganizationRole.all_repo_read_role.octicon
    end

    test "returns default octicon if role is not in SYSTEM_ROLE_METADATA" do
      custom_role = create_custom_org_role(owner: @org, role_name: "custom role")
      assert_equal "note", custom_role.octicon
    end
  end

  context "enterprise_custom_organization_roles feature", skip_if_feature_disabled: :enterprise_custom_organization_roles do
    test "enterprise can create org role" do
      org = create(:business_plus_organization)
      org.business = GitHub.single_business_environment? ? GitHub.global_business : create(:business)

      assert_difference "Role.count", 1 do
        OrganizationRole.create!({
          name: "enterprise role",
          owner_id: org.business.id,
          owner_type: "Business"
        })
      end
    end
  end

  context "scopes" do
    test "custom_roles_for_org includes roles owned by the org" do
      org = create(:business_plus_organization)
      org.business = GitHub.single_business_environment? ? GitHub.global_business : create(:business)

      org_role = OrganizationRole.create!({
        name: "org role",
        owner_id: org,
        owner_type: "Organization"
      })

      assert_includes OrganizationRole.custom_roles_for_org(org), org_role

      if GitHub.flipper[:enterprise_custom_organization_roles].enabled?
        enterprise_role = OrganizationRole.create!({
          name: "enterprise role",
          owner_id: org.business.id,
          owner_type: "Business"
        })
        refute_includes OrganizationRole.custom_roles_for_org(org), enterprise_role
      end
    end

    test "custom_roles_for_enterprise includes roles owned by the business" do
      org = create(:business_plus_organization)
      org.business = GitHub.single_business_environment? ? GitHub.global_business : create(:business)

      org_role = OrganizationRole.create!({
        name: "org role",
        owner_id: org.id,
        owner_type: "Organization"
      })

      refute_includes OrganizationRole.custom_roles_for_enterprise(org.business), org_role

      if GitHub.flipper[:enterprise_custom_organization_roles].enabled?
        enterprise_role = OrganizationRole.create!({
          name: "enterprise role",
          owner_id: org.business.id,
          owner_type: "Business"
        })
        assert_includes OrganizationRole.custom_roles_for_enterprise(org.business), enterprise_role
      end
    end
  end
end
