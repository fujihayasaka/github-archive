# typed: false
# frozen_string_literal: true

require "test_helper"

class PermissionsGrantersRoleGranterTest < GitHub::TestCase
  PackageMock = Struct.new(:author_id, :ecosystem, :id, :namespace, :name)
  include DogstatsTestHelpers
  include AuditLog::IntegrationTestHelpers
  fixtures do
    @user = create(:user)
    @admin = create(:user)
    @org = create(:business_plus_organization)
    @repo = create(:private_repository, :minimal, owner: @org)
    @org.add_member(@user)
    @org.add_member(@user, action: :admin)

    @read   = Role.read_role
    @write  = Role.write_role
    @triage = Role.triage_role
    @package_reader = Role.presets.find_by(name: "package_reader")
    @custom_repo_role = create(:custom_repository_role, owner_id: @org.id, owner_type: "Organization", base_role_id: Role.maintain_role.id)

    # Create a dummy organization role.
    @dummy_preset_org_role = OrganizationRole.new(name: "dummy_preset_org_role", owner: nil)
    @dummy_preset_org_role.save!(validate: false) # Bypass validation (specifically `validates :owner`) to create a preset role.

    # Add the role name into the internal and system role sets. Also update the UserRole target type for this role.
    Role::INTERNAL_ROLES << @dummy_preset_org_role.name
    Role::SYSTEM_ROLES << @dummy_preset_org_role.name
    UserRole::INTERNAL_ROLE_TARGET_TYPE[@dummy_preset_org_role.name.to_sym] = "Organization"

    @custom_org_role = OrganizationRole.create!(name: "custom_org_role", owner: @org, owner_type: "Organization")

    @business = create(:business)
    enable_feature_flag(:enterprise_teams_crud, @business)

    @business_org = create(:business_plus_organization, business: @business)
    @business_team = BusinessTeam.create!(name: "business-team", business: @business, organization_selection_type: :all)
    @business_org_repo = create(:private_repository, :minimal, owner: @business_org)
    @business_org_custom_repo_role = create(:custom_repository_role, owner_id: @business_org.id, owner_type: "Organization", base_role_id: Role.maintain_role.id)
    @business_org_custom_org_role = OrganizationRole.create!(name: "custom_org_role_business_org", owner: @business_org, owner_type: "Organization")

  end

  setup do
    @org_package = PackageRegistry::Package.new(PackageMock.new(
      author_id: @user.id,
      ecosystem: :CONTAINER,
      id: 3,
      namespace: @org.login,
      name: "foo",
    ))
  end

  context "new" do
    test "can be instantiated without a role" do
      assert_nothing_raised { Permissions::Granters::RoleGranter.new(actor: @user, target: @repo) }
    end

    test "can be instantiated with a system role" do
      assert_nothing_raised { Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: @read) }
    end

    test "can be instantiated with a custom role" do
      assert_nothing_raised { Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: @custom_repo_role) }
    end

    test "can be instantiated with an internal role" do
      assert_nothing_raised { Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: @package_reader) }
    end

    test "can be instantiated with an internal organization role" do
      assert_nothing_raised { Permissions::Granters::RoleGranter.new(actor: @user, target: @org, role: @dummy_preset_org_role) }
    end

    test "can be instantiated with a custom organization role" do
      assert_nothing_raised { Permissions::Granters::RoleGranter.new(actor: @user, target: @org, role: @custom_org_role) }
    end

    test "raises if role is not a valid Role" do
      assert_raises(ArgumentError) { Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: Object.new) }
    end

    test "raises if role that needs org owner is not org owned" do
      assert_raises(ArgumentError) { Permissions::Granters::RoleGranter.new(actor: @user, target: create(:repository, :minimal), role: @custom_repo_role) }
    end
  end

  context "grant!" do
    test "creates a new user role record for enterprise owned roles" do
      Role::SYSTEM_ROLES << "test_enterprise_role"
      Role::INTERNAL_ROLES << "test_enterprise_role"

      ent_role = Role.create!(
        name: "test_enterprise_role",
        target_type: "Business"
      )
      result = Permissions::Granters::RoleGranter.new(actor: @user, target: @business, role: ent_role).grant!
      assert_equal true, result.success?
    end

    test "creates a new user role record for org owned roles" do
      result = Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: @custom_repo_role).grant!
      assert_equal true, result.success?
    end

    test "creates a new user role record for preset role" do
      GitHub.dogstats.stubs(:increment)
      GitHub.dogstats.expects(:increment).
        with("user_roles.granted", tags: ["result:success", "actor_type:#{@user.class.name}", "role_name:triage", "target_type:#{@repo.class.name}"])

      result = Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: @triage).grant!

      assert result.success?, "User should be granted role"
    end

    test "can grant a role to a team" do
      team = create(:team, organization: @org)
      result = Permissions::Granters::RoleGranter.new(actor: team, target: @repo, role: @custom_repo_role).grant!

      assert_equal true, result.success?
    end

    test "can grant a role to a business team" do
      result = Permissions::Granters::RoleGranter.new(actor: @business_team, target: @business_org_repo, role: @business_org_custom_repo_role).grant!

      assert_equal true, result.success?
    end

    test "can grant an internal organization role to a user" do
      user = create(:user)
      @org.add_member(user)

      result = Permissions::Granters::RoleGranter.new(actor: user, target: @org, role: @dummy_preset_org_role).grant!

      assert_equal true, result.success?

      user_role = UserRole.find_by(role_id: @dummy_preset_org_role.id, actor_id: user.id)
      assert_equal @dummy_preset_org_role, user_role.role
      assert_equal user, user_role.actor
      assert_equal "Organization", user_role.target_type
    end

    test "can grant an internal organization role to a team" do
      team = create(:team, organization: @org)

      result = Permissions::Granters::RoleGranter.new(actor: team, target: @org, role: @dummy_preset_org_role).grant!

      assert_equal true, result.success?

      user_role = UserRole.find_by(role_id: @dummy_preset_org_role.id, actor_id: team.id)
      assert_equal @dummy_preset_org_role, user_role.role
      assert_equal team, user_role.actor
      assert_equal "Organization", user_role.target_type
    end

    test "can grant an internal organization role to a business team" do
      org_business_team = BusinessTeam.create!(name: "org-business-team", business: @business, organization_selection_type: :all)

      result = Permissions::Granters::RoleGranter.new(actor: org_business_team, target: @org, role: @dummy_preset_org_role).grant!

      assert_equal true, result.success?

      user_role = UserRole.find_by(role_id: @dummy_preset_org_role.id, actor_id: org_business_team.id)
      assert_equal @dummy_preset_org_role, user_role.role
      assert_equal org_business_team, user_role.actor
      assert_equal "Organization", user_role.target_type
      assert_equal "BusinessTeam", user_role.actor_type
    end

    test "can grant a custom organization role to a user" do
      user = create(:user)
      @org.add_member(user)

      result = Permissions::Granters::RoleGranter.new(actor: user, target: @org, role: @custom_org_role).grant!

      assert_equal true, result.success?

      user_role = UserRole.find_by(role_id: @custom_org_role.id, actor_id: user.id)
      assert_equal @custom_org_role, user_role.role
      assert_equal user, user_role.actor
      assert_equal "Organization", user_role.target_type
    end

    test "creates an audit log entry when granting a custom organization role to a user" do
      user = create(:user)
      @org.add_member(user)

      events = assert_performed_audit_entries(count: 1, only: "organization_role.assign") do
        Permissions::Granters::RoleGranter.new(actor: user, target: @org, role: @custom_org_role).grant!
      end

      expected_payload = {
        organization_role_id: @custom_org_role.id,
        organization_role_name: @custom_org_role.name,
        org: @org.display_login,
        org_id: @org.id,
        user: user.display_login,
        user_id: user.id
      }

      assert_subset_hash expected_payload, events.first
    end

    test "can grant a custom organization role to a team" do
      team = create(:team, organization: @org)

      result = Permissions::Granters::RoleGranter.new(actor: team, target: @org, role: @custom_org_role).grant!

      assert_equal true, result.success?

      user_role = UserRole.find_by(role_id: @custom_org_role.id, actor_id: team.id)
      assert_equal @custom_org_role, user_role.role
      assert_equal team, user_role.actor
      assert_equal "Organization", user_role.target_type
    end

    test "can grant a custom organization role to a business team" do
      org_business_team = BusinessTeam.create!(name: "org-business-team", business: @business, organization_selection_type: :all)

      result = Permissions::Granters::RoleGranter.new(actor: org_business_team, target: @business_org, role: @business_org_custom_org_role).grant!

      assert_equal true, result.success?

      user_role = UserRole.find_by(role_id: @business_org_custom_org_role.id, actor_id: org_business_team.id)
      assert_equal @business_org_custom_org_role, user_role.role
      assert_equal org_business_team, user_role.actor
      assert_equal "Organization", user_role.target_type
      assert_equal "BusinessTeam", user_role.actor_type
    end

    test "creates an audit log event when granting a custom organization role to a team" do
      team = create(:team, organization: @org)
      events = assert_performed_audit_entries(count: 1, only: "organization_role.assign") do
        Permissions::Granters::RoleGranter.new(actor: team, target: @org, role: @custom_org_role).grant!
      end

      expected_payload = {
        organization_role_id: @custom_org_role.id,
        organization_role_name: @custom_org_role.name,
        org: @org.display_login,
        org_id: @org.id,
        team: team.combined_slug,
        team_id: team.id
      }

      assert_subset_hash expected_payload, events.first
    end

    test "raises if granting a custom organization role against a repo" do
      assert_raises do
        Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: @custom_org_role).grant!
      end

      user_role = UserRole.find_by(role_id: @custom_org_role.id, actor_id: @user.id)
      assert_nil user_role
    end

    test "raises if granting a custom repo role against an org" do
      assert_raises do
        Permissions::Granters::RoleGranter.new(actor: @user, target: @org, role: @custom_repo_role).grant!
      end

      user_role = UserRole.find_by(role_id: @custom_repo_role.id, actor_id: @user.id)
      assert_nil user_role
    end

    test "raises if all args are not passed" do
      assert_raises(ArgumentError) do
        Permissions::Granters::RoleGranter.new(actor: @user, target: diff, role: nil).grant!
      end
    end

    test "generates a datadog metric when granting fails" do
      GitHub.dogstats.stubs(:increment)
      GitHub.dogstats.expects(:increment).
        with("user_roles.granted", tags: ["result:fail", "actor_type:#{@user.class.name}", "role_name:triage", "target_type:#{@repo.class.name}"])

      UserRole.any_instance.stubs(:save!).returns(false)

      assert_raises Permissions::Granters::RoleGranter::GrantFailure do
        Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: @triage).grant!
      end
    end

    test "can grant a custom role with its permissions, and associated ability record" do
      skip if TestEnv.all_repo_roles_test?

      custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: @org.id, owner_type: "Organization", base_role_id: @read.id)
      GitHub.dogstats.stubs(:increment)
      GitHub.dogstats.expects(:increment).
        with("user_roles.granted", tags: ["result:success", "actor_type:#{@user.class.name}", "role_name:custom_role", "target_type:#{@repo.class.name}"])

      result = Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: custom_role).grant!
      user_role = UserRole.find_by(actor: @user, role: custom_role).role

      assert_equal true, result.success?
      assert_equal custom_role.permissions, user_role.permissions
      assert_equal @read, user_role.base_role, "base role of custom role should be read"
      assert_equal user_role.base_role.name, Ability.where(actor_id: @user, actor_type: "User", subject_id: @repo.id, subject_type: "Repository").first.action
    end

    test "can grant a custom role with a name of an internal role" do
      skip if TestEnv.all_repo_roles_test?

      custom_role = create(:custom_repository_role, name: Role::PACKAGES_SYSTEM_ROLES.first, owner_id: @org.id, owner_type: "Organization", base_role_id: @write.id)
      result = Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: custom_role).grant!

      user_role = UserRole.find_by(actor: @user, role: custom_role).role

      assert_equal true, result.success?
      assert_equal user_role.base_role.name, Ability.where(actor_id: @user, actor_type: "User", subject_id: @repo.id, subject_type: "Repository").first.action
    end

    test "can grant a custom role with write base role, and associated ability record" do
      skip if TestEnv.all_repo_roles_test?

      custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: @org.id, owner_type: "Organization", base_role_id: @write.id)
      result = Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: custom_role).grant!

      user_role = UserRole.find_by(actor: @user, role: custom_role).role

      assert_equal true, result.success?
      assert_equal custom_role.permissions, user_role.permissions
      assert_equal user_role.base_role.name, Ability.where(actor_id: @user, actor_type: "User", subject_id: @repo.id, subject_type: "Repository").first.action
    end

    test "can grant a custom role with triage base role, and associated ability record" do
      skip if TestEnv.all_repo_roles_test?

      custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: @org.id, owner_type: "Organization", base_role_id: @triage.id)
      result = Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: custom_role).grant!

      user_role = UserRole.find_by(actor: @user, role: custom_role).role

      assert_equal true, result.success?
      assert_equal "read", Ability.where(actor_id: @user, actor_type: "User", subject_id: @repo.id, subject_type: "Repository").first.action
    end

    test "can grant an integration role to a user", skip_if_feature_disabled: :org_app_management_via_fgps do
      user = create(:user)
      app = create(:integration)

      result = Permissions::Granters::RoleGranter
        .new(actor: user, target: app, role: Role.app_owner_role)
        .grant!

      assert_predicate result, :success?
    end

    test "can't grant a role on a user-owned repo" do
      user_owned_repo = create(:repository, :minimal, owner: create(:user))

      assert_raises(ArgumentError) do
        Permissions::Granters::RoleGranter.new(actor: @user, target: user_owned_repo, role: @custom_repo_role).grant!
      end
    end

    test "will not grant a role if the associated ability record fails to save" do
      skip if TestEnv.all_repo_roles_test?

      custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: @org.id, owner_type: "Organization", base_role_id: @triage.id)

      # force the ability record to raise, to simulate it not saving
      Ability::Grant.expects(:apply_abilities_to_ancestors).raises(ArgumentError)

      assert_raises(ArgumentError) do
        Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: custom_role).grant!
      end

      refute UserRole.find_by(actor: @user, role: custom_role)
      refute Ability.find_by(actor: @user, subject: @repo)
    end


    test "will save ability record if role fails to grant (bug)" do
      # this test demonstrates buggy existing behavior. We would like the user_role and ability record to both be added, or neither.
      # Please update this test to the desired behavior if addressing this bug.
      skip if TestEnv.all_repo_roles_test?
      skip if GitHub.enterprise?

      custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: @org.id, owner_type: "Organization", base_role_id: @triage.id)

      UserRole.any_instance.expects(:save!).raises(ArgumentError)

      assert_raises(ArgumentError) do
        Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: custom_role).grant!
      end

      refute UserRole.find_by(actor: @user, role: custom_role)
      assert Ability.find_by(actor: @user, subject: @repo)
    end

    test "with an Org as a target" do
      only = [SyncOrganizationDefaultRepositoryPermissionJob]
      perform_enqueued_jobs(only: only) { @org.update_default_repository_permission(:write, actor: @admin) }

      codespace_role = Role.codespace_org_creator_role
      result = Permissions::Granters::RoleGranter.new(actor: @user, target: @org, role: codespace_role).grant!

      assert_equal true, result.success?
      assert UserRole.find_by(actor: @user, target_type: "Organization", target_id: @org.id, role_id: codespace_role.id)
    end

    test "with an invalid actor for an internal role" do
      codespace_role = Role.codespace_org_creator_role

      # Permissions::Participant#can_be_granted_permission_over! will cause NoMethodError
      # to be raised. Ability::Actor includes this mixin.
      assert_raises(NoMethodError) do
        Permissions::Granters::RoleGranter.new(actor: @repo, target: @org, role: codespace_role).grant!
      end
    end

    test "with an invalid target for an internal role" do
      codespace_role = Role.codespace_org_creator_role

      # target validation is done prior to creating the UserRole
      assert_raises(::Permissions::Granters::RoleGranter::GrantFailure) do
        Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: codespace_role).grant!
      end
    end

    context "with a PORO as target" do
      test "can grant a role to a user" do
        result = Permissions::Granters::RoleGranter.new(actor: @user, target: @org_package, role: @package_reader).grant!

        assert_equal true, result.success?
        assert UserRole.find_by(actor: @user, target_type: "Package", target_id: 3, role_id: @package_reader.id)
      end

      test "can grant a role to a team" do
        team = create(:team, organization: @org)
        result = Permissions::Granters::RoleGranter.new(actor: team, target: @org_package, role: @package_reader).grant!

        assert_equal true, result.success?
        assert UserRole.find_by(actor: team, target_type: "Package", target_id: 3, role_id: @package_reader.id)
      end

      test "can grant a role where owner is a user" do
        result = Permissions::Granters::RoleGranter.new(actor: @user, target: @org_package, role: @package_reader).grant!

        assert_equal true, result.success?
        assert UserRole.find_by(actor: @user, target_type: "Package", target_id: 3, role_id: @package_reader.id)
      end
    end

    context "default org role" do
      test "will raise if role is below org default" do
        @org.config.set(Configurable::DefaultRepositoryPermission::KEY, :admin, @admin)
        SyncOrganizationDefaultRepositoryPermissionJob.perform_now(@org.id, Organization.name, @admin.id)

        assert_raises(::Permissions::Granters::RoleGranter::GrantFailure) do
          Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: @triage).grant!
        end
      end

      test "will raise if the base_role of custom role is below org default" do
        @org.config.set(Configurable::DefaultRepositoryPermission::KEY, :admin, @admin)
        SyncOrganizationDefaultRepositoryPermissionJob.perform_now(@org.id, Organization.name, @admin.id)

        assert_raises(::Permissions::Granters::RoleGranter::GrantFailure) do
          Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: @custom_repo_role).grant!
        end
      end

      test "will not raise if role is below org default for a team" do
        @org.config.set(Configurable::DefaultRepositoryPermission::KEY, :write, @admin)
        SyncOrganizationDefaultRepositoryPermissionJob.perform_now(@org.id, Organization.name, @admin.id)
        team = create(:team, organization: @org)
        result = Permissions::Granters::RoleGranter.new(actor: team, target: @repo, role: @triage).grant!

        assert_equal true, result.success?
      end

      test "will not raise if role is below org default for an outside collab" do
        @org.config.set(Configurable::DefaultRepositoryPermission::KEY, :write, @admin)
        SyncOrganizationDefaultRepositoryPermissionJob.perform_now(@org.id, Organization.name, @admin.id)
        user = create(:user)
        result = Permissions::Granters::RoleGranter.new(actor: user, target: @repo, role: @triage).grant!

        assert_equal true, result.success?
      end
    end

    context "handling race conditions" do
      test "will return success if an ActiveRecord::RecordNotUnique error is raised and the rescue FF is enabled" do
        enable_feature_flag(:rescue_not_unique_user_role_grants)
        Permissions::Granters::RoleGranter.any_instance.stubs(:grant_user_role_unless_exists).raises(ActiveRecord::RecordNotUnique)

        result = Permissions::Granters::RoleGranter.new(actor: @user, target: @org_package, role: @package_reader).grant!
        assert_equal true, result.success?
      end

      test "will return a ActiveRecord::RecordNotUnique error if it is raised and the rescue FF is not enabled" do
        Permissions::Granters::RoleGranter.any_instance.stubs(:grant!).raises(ActiveRecord::RecordNotUnique)

        assert_raises ActiveRecord::RecordNotUnique do
          Permissions::Granters::RoleGranter.new(actor: @user, target: @org_package, role: @package_reader).grant!
        end
      end
    end
  end

  context "revoke_if_exists!" do
    test "revokes the user role" do
      user_role = create(:user_role, actor: @user, role: @custom_repo_role, target: @repo)
      GitHub.dogstats.stubs(:increment)
      GitHub.dogstats.expects(:increment).with("user_roles.revoked", tags: ["role_name:custom_role", "result:success", "actor_type:User", "target_type:Repository"])

      result = Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: @custom_repo_role).revoke_if_exists!

      assert_equal true, result.success?
    end

    test "returns a success even if user role does not exist" do
      assert_empty @user.user_roles
      result = Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: @custom_repo_role).revoke_if_exists!
      assert_predicate result, :success?
    end

    test "revokes user role without role name being passed" do
      user_role = create(:user_role, actor: @user, role: @custom_repo_role, target: @repo)

      result = Permissions::Granters::RoleGranter.new(actor: @user, target: @repo).revoke_if_exists!

      assert_equal true, result.success?
      refute UserRole.find_by(role: @custom_repo_role, actor: @user, target: @repo).present?
    end

    test "revokes multiple user roles" do
      another_org_role = create(:custom_organization_role, owner_id: @org.id)
      assert_predicate Permissions::Granters::RoleGranter.new(actor: @user, target: @org, role: @custom_org_role).grant!, :success?
      assert_predicate Permissions::Granters::RoleGranter.new(actor: @user, target: @org, role: another_org_role).grant!, :success?

      assert_predicate UserRole.where(actor: @user, target_type: Organization, target_id: @org.id), :many?

      result = Permissions::Granters::RoleGranter.new(actor: @user, target: @org).revoke_if_exists!
      assert_equal true, result.success?
      assert_equal false, UserRole.exists?(actor_id: @user.id, target_type: Organization, target_id: @org.id)
      assert_dogstats_distribution("user_role.revoke_all_roles", tags: [
        "result:success",
        "count:2"
      ])
    end

    test "revokes role for a team" do
      skip if TestEnv.all_repo_roles_test?

      team = create(:team, organization: @org)
      test_role_revoked(team, @repo, @custom_repo_role)
    end

    test "revokes a user role for a preset org role" do
      user = create(:user)
      test_role_revoked(user, @org, @dummy_preset_org_role)
    end

    test "revokes a team user role for a preset org role" do
      team = create(:team, organization: @org)
      test_role_revoked(team, @org, @dummy_preset_org_role)
    end

    test "revokes a business team user role for a preset org role" do
      org_business_team = BusinessTeam.create!(name: "org-business-team", business: @business, organization_selection_type: :all)
      test_role_revoked(org_business_team, @org, @dummy_preset_org_role)
    end

    test "revokes a business team user role for a custom org role" do
      org_business_team = BusinessTeam.create!(name: "org-business-team", business: @business, organization_selection_type: :all)
      test_role_revoked(org_business_team, @business_org, @business_org_custom_org_role)
    end

    test "revokes a user role for a custom org role" do
      user = create(:user)
      test_role_revoked(user, @org, @custom_org_role)
    end

    test "creates an audit log entry for organization role revocation for user" do
      user = create(:user)
      events = assert_performed_audit_entries(count: 1, only: "organization_role.revoke") do
        test_role_revoked(user, @org, @custom_org_role)
      end

      expected_payload = {
        organization_role_id: @custom_org_role.id,
        organization_role_name: @custom_org_role.name,
        org: @org.display_login,
        org_id: @org.id,
        user: user.display_login,
        user_id: user.id
      }

      assert_subset_hash expected_payload, events.first
    end

    test "revokes a team user role for a custom org role" do
      team = create(:team, organization: @org)
      test_role_revoked(team, @org, @custom_org_role)
    end

    test "creates an audit log entry for organization role revocation for team" do
      team = create(:team, organization: @org)
      events = assert_performed_audit_entries(count: 1, only: "organization_role.revoke") do
        test_role_revoked(team, @org, @custom_org_role)
      end

      expected_payload = {
        organization_role_id: @custom_org_role.id,
        organization_role_name: @custom_org_role.name,
        org: @org.display_login,
        org_id: @org.id,
        team: team.combined_slug,
        team_id: team.id
      }

      assert_subset_hash expected_payload, events.first
    end

    test "generates a datadog metric when revoking fails" do
      GitHub.dogstats.stubs(:increment)
      GitHub.dogstats.expects(:increment).with("user_roles.revoked", tags: ["role_name:triage", "result:fail", "actor_type:User", "target_type:Repository"])

      create(:user_role, actor: @user, role: @triage, target: @repo)

      UserRole.any_instance.stubs(:destroy).returns(false)
      assert_raises Permissions::Granters::RoleGranter::GrantFailure do
        Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: @triage).revoke_if_exists!
      end
    end

    test "raises if all args are not passed" do
      assert_raises(ArgumentError) do
        Permissions::Granters::RoleGranter.new(actor: @user, target: nil, role: nil).revoke_if_exists!
      end
    end

    context "with a PORO as target" do
      test "revokes role for a user" do
        user_role = create(:user_role, actor: @user, role: @package_reader, target_type: "Package", target_id: 3)

        result = Permissions::Granters::RoleGranter.new(actor: @user, target: @org_package, role: @package_reader).revoke_if_exists!

        assert_equal true, result.success?
        assert_raises ActiveRecord::RecordNotFound do
          user_role.reload
        end
      end

      test "revokes role for a team" do
        team = create(:team, organization: @org)
        user_role = create(:user_role, actor: team, role: @package_reader, target_type: "Package", target_id: 3)

        result = Permissions::Granters::RoleGranter.new(actor: team, target: @org_package, role: @package_reader).revoke_if_exists!

        assert_equal true, result.success?
        assert_raises ActiveRecord::RecordNotFound do
          user_role.reload
        end
      end

      test "where owner is a user" do
        user_role = create(:user_role, actor: @user, role: @package_reader, target_type: "Package", target_id: 3)
        user_package = PackageRegistry::Package.new(PackageMock.new(
          author_id: @user.id,
          ecosystem: :CONTAINER,
          id: 3,
          namespace: @user.login,
          name: "foo",
        ))

        result = Permissions::Granters::RoleGranter.new(actor: @user, target: user_package, role: @package_reader).revoke_if_exists!

        assert_equal true, result.success?
        assert_raises ActiveRecord::RecordNotFound do
          user_role.reload
        end
      end
    end
  end

  context "#grant_unless_exists!" do
    test "grant a user role if it does not already exist on user" do
      skip if TestEnv.all_repo_roles_test?

      assert_empty @user.user_roles
      result = Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: @custom_repo_role).grant_unless_exists!

      assert_predicate result, :success?
      assert UserRole.find_by(actor: @user, role_id: @custom_repo_role.id)
    end

    test "returns a success even if user role already exists on user" do
      user_role = create(:user_role, actor: @user, role: @custom_repo_role, target: @repo)
      assert_equal [user_role], @user.user_roles
      result = Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: @custom_repo_role).grant_unless_exists!

      assert_predicate result, :success?
      assert_equal [user_role], @user.user_roles
    end

    test "raises if all args are not passed" do
      assert_raises(ArgumentError) do
        Permissions::Granters::RoleGranter.new(actor: @user, target: nil, role: nil).grant_unless_exists!
      end
    end
  end

  context "cache clearing logic" do
    test "permission cache gets cleared when a role is granted" do
      PermissionCache.enable do
        PermissionCache.set(["test"], "something")
        assert_equal "something", PermissionCache.get(["test"])
        user_role = create(:user_role, actor: @user, role: @custom_repo_role, target: @repo)
        assert_equal [user_role], @user.user_roles
        assert_nil PermissionCache.get(["test"])
      end
    end

    test "permission cache gets cleared when a role is revoked" do
      user_role = create(:user_role, actor: @user, role: @custom_repo_role, target: @repo)
      assert_equal [user_role], @user.user_roles
      PermissionCache.enable do
        PermissionCache.set(["test"], "something")
        assert_equal "something", PermissionCache.get(["test"])
        result = Permissions::Granters::RoleGranter.new(actor: @user, target: @repo, role: @custom_repo_role).revoke_if_exists!
        assert_predicate result, :success?
        assert_nil PermissionCache.get(["test"])
      end
    end
  end

  private

  def test_role_revoked(actor, target, role)
    result = Permissions::Granters::RoleGranter.new(actor: actor, target: target, role: role).grant!
    assert_equal true, result.success?
    assert_equal true, UserRole.exists?(role_id: role.id, actor_id: actor.id, target_id: target.id)

    result = Permissions::Granters::RoleGranter.new(actor: actor, target: target).revoke_if_exists!
    assert_equal true, result.success?
    assert_equal false, UserRole.exists?(role_id: role.id, actor_id: actor.id, target_id: target.id)
  end
end
