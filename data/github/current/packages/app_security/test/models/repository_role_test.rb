# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryRoleTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  setup do
    if GitHub.enterprise?
      GitHub::Plan.stubs(:business_plus).raises(StandardError.new("No plan found for business_plus"))
    end
  end

  context "validations" do
    if GitHub.enterprise?
      test "can not create more than maximum custom roles for enterprise plans" do
        org = create(:organization, plan: "enterprise")
        RepositoryRole::ENTERPRISE_CUSTOM_REPO_ROLE_LIMIT.times { create_custom_role(owner: org) }
        assert_equal RepositoryRole::ENTERPRISE_CUSTOM_REPO_ROLE_LIMIT, RepositoryRole.custom_roles_for_org(org).count

        role = build(:role, owner_id: org.id, owner_type: "Organization")
        refute_predicate role, :valid?
        assert_equal "Owner is already at the maximum number of custom roles", role.errors.full_messages.to_sentence
      end
    else
      test "can not create more than maximum custom roles for business_plus plans" do
        org = create(:business_plus_organization)
        RepositoryRole::BUSINESS_PLUS_CUSTOM_REPO_ROLE_LIMIT.times { create_custom_role(owner: org) }
        assert_equal RepositoryRole::BUSINESS_PLUS_CUSTOM_REPO_ROLE_LIMIT, RepositoryRole.custom_roles_for_org(org).count

        role = build(:role, owner_id: org.id, owner_type: "Organization")
        refute_predicate role, :valid?
        assert_equal "Owner is already at the maximum number of custom roles", role.errors.full_messages.to_sentence
      end
    end
  end

  context "retrieving custom roles" do
    test ".custom_roles_for_org returns only custom repo roles for an org" do
      org = create(:business_plus_organization)
      other_org = create(:business_plus_organization)
      custom_role = create_custom_role(owner: org)
      create(:custom_organization_role, owner_id: org.id, owner_type: "Organization")

      create_custom_role(owner: other_org)

      roles = RepositoryRole.custom_roles_for_org(org)
      assert_equal 1, roles.count
      assert_equal roles.first, custom_role
    end

    test ".custom_role_by_name can only retrieve repo roles" do
      org = create(:business_plus_organization)
      custom_org_role = create(:custom_organization_role, owner_id: org.id, owner_type: "Organization")
      custom_repo_role = create_custom_role(owner: org)

      org_role = RepositoryRole.custom_role_by_name(custom_org_role.name, org: org)
      repo_role = RepositoryRole.custom_role_by_name(custom_repo_role.name, org: org)

      assert_nil org_role
      assert_equal custom_repo_role, repo_role
    end
  end

  context ".custom_org_role_limit_for" do
    if GitHub.billing_enabled?
      test "business plus plan custom role limit" do
        assert_equal RepositoryRole::BUSINESS_PLUS_CUSTOM_REPO_ROLE_LIMIT, RepositoryRole.custom_role_limit_for_org(create(:business_plus_organization))
      end

      test "business plan custom role limit" do
        assert_equal 0, RepositoryRole.custom_role_limit_for_org(create(:organization, plan: "business"))
      end

      test "free plan custom role limit" do
        assert_equal 0, RepositoryRole.custom_role_limit_for_org(create(:organization, plan: "free"))
      end

      test "legacy plan custom role limit" do
        assert_equal 0, RepositoryRole.custom_role_limit_for_org(create(:organization, plan: "bronze"))
      end
    end

    if GitHub.enterprise?
      test "enterprise custom role limit" do
        assert RepositoryRole::ENTERPRISE_CUSTOM_REPO_ROLE_LIMIT, RepositoryRole.custom_role_limit_for_org(create(:organization))
      end
    end
  end

  context "highest role" do
    test "returns the highest role" do
      org = create(:business_plus_organization)
      read_custom_role = create(:custom_repository_role, base_role_id: Role.read_role.id, owner_id: org.id, owner_type: "Organization")
      write_custom_role = create(:custom_repository_role, base_role_id: Role.write_role.id, owner_id: org.id, owner_type: "Organization")
      newer_write_custom_role = create(:custom_repository_role, base_role_id: Role.write_role.id, owner_id: org.id, owner_type: "Organization")

      assert_nil RepositoryRole.highest_role(nil)
      assert_nil RepositoryRole.highest_role([])

      # system with higher base role
      assert_highest_role Role.write_role, [read_custom_role, Role.write_role]

      # custom role with higher base
      assert_highest_role write_custom_role, [read_custom_role, write_custom_role]

      # custom role with same base as system
      assert_highest_role write_custom_role, [write_custom_role, Role.write_role]

      # custom roles with same base
      assert_highest_role newer_write_custom_role, [write_custom_role, newer_write_custom_role]
    end
  end

  private def assert_highest_role(expected, roles)
    assert_equal expected, RepositoryRole.highest_role(roles)
    assert_equal expected, RepositoryRole.highest_role(roles.reverse)
  end
end
