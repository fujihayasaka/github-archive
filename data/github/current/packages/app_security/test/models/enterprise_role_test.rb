# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseRoleTest < GitHub::TestCase

  fixtures do
    @business = create(:business)
    @organization = create(:business_plus_organization, business: @business)
    @user = create(:user)
    # Using an org team for now
    @team = create(:team, organization: @organization, privacy: :closed)
  end

  test "can not create a Custom Enterprise Role" do
    GitHub.flipper[:custom_enterprise_role_feature].disable
    assert_raises ActiveRecord::RecordInvalid do
      Role.create!(
        name: "test enterprise role",
        description: "test ent role description",
        owner_id: @business.id,
        owner_type: "Business",
        base_role_id: nil,
        target_type: "Business"
      )
    end
  end

  test "can create a Custom Enterprise Role when Limit is not reached" do
    GitHub.flipper[:custom_enterprise_role_feature].enable
    # Limit for Custom Enterprise Roles is currently 0, so stubbing here
    EnterpriseRole.stubs(:custom_role_limit_for_enterprise).returns(5)
    assert_nothing_raised do
      Role.create!(
        name: "test enterprise role",
        description: "test ent role description",
        owner_id: @business.id,
        owner_type: "Business",
        base_role_id: nil,
        target_type: "Business"
      )
    end
  end

  test "can register an valid Enterprise Role" do
    mod_sys_roles = Role::INTERNAL_ROLES + %w(test_enterprise_role)
    Role.stub_const(:SYSTEM_ROLES, mod_sys_roles) do # We don't have a real enterprise role yet
      ent_role = Role.create!(
        name: "test_enterprise_role",
        target_type: "Business"
      )
      assert ent_role.instance_of?(EnterpriseRole)

      fgp = Permissions::FineGrainedPermissionIm.new("ent_action_#{SecureRandom.hex(5)}", target_type: "Business")
      Permissions::FineGrainedPermissionIm.with_testing_permission(fgp) do
        rp = RolePermission.create!(role: ent_role, action: fgp.action)
        assert_same_elements [rp], ent_role.permissions
      end
    end
  end

  context "#assignment" do
    test "assigning a stubbed system role" do
      mod_sys_roles = Role::SYSTEM_ROLES + %w(test_enterprise_role)
      Role.stub_const(:SYSTEM_ROLES, mod_sys_roles) do # We don't have a real enterprise role yet
        ent_role = Role.create!(
          name: "test_enterprise_role",
          target_type: "Business"
        )

        assert_nothing_raised do
          create(:user_role, actor: @user, role: ent_role, target_type: "Business", target_id: @business.id)
          create(:user_role, actor: @team, role: ent_role, target_type: "Business", target_id: @business.id)
        end

        assert_same_elements([@user.id], ent_role.user_ids)
        assert_same_elements([@team.id], ent_role.user_roles.where(actor_type: "Team").pluck(:actor_id))
      end
    end

    test "assigning a stubbed internal role" do
      mod_int_roles = Role::INTERNAL_ROLES + %w(test_enterprise_role)
      Role.stub_const(:INTERNAL_ROLES, mod_int_roles) do # We don't have a real enterprise role yet
        sys_roles = Role::SYSTEM_ROLES + %w(test_enterprise_role)

        Role.stub_const(:SYSTEM_ROLES, sys_roles) do # We don't have a real enterprise role yet
          ent_role = Role.create!(
            name: "test_enterprise_role",
            target_type: "Business"
          )

          assert_nothing_raised do
            create(:user_role, actor: @user, role: ent_role, target_type: "Business", target_id: @business.id)
            create(:user_role, actor: @team, role: ent_role, target_type: "Business", target_id: @business.id)
          end

          assert_same_elements([@user.id], ent_role.user_ids)
          assert_same_elements([@team.id], ent_role.user_roles.where(actor_type: "Team").pluck(:actor_id))
        end
      end
    end

    test "assigning multiple stubbed roles" do
      mod_sys_roles = Role::SYSTEM_ROLES + %w(test_enterprise_role test_ent_role_2)
      Role.stub_const(:SYSTEM_ROLES, mod_sys_roles) do # We don't have a real enterprise role yet
        ent_role = Role.create!(
          name: "test_enterprise_role",
          target_type: "Business"
        )
        ent_rol_2 = Role.create!(
          name: "test_ent_role_2",
          target_type: "Business"
        )

        assert_nothing_raised do
          create(:user_role, actor: @user, role: ent_role, target_type: "Business", target_id: @business.id)
          create(:user_role, actor: @team, role: ent_role, target_type: "Business", target_id: @business.id)
          create(:user_role, actor: @user, role: ent_rol_2, target_type: "Business", target_id: @business.id)
          create(:user_role, actor: @team, role: ent_rol_2, target_type: "Business", target_id: @business.id)
        end

        assert_same_elements([@user.id], ent_role.user_ids)
        assert_same_elements([@team.id], ent_role.user_roles.where(actor_type: "Team").pluck(:actor_id))
        assert_same_elements([@user.id], ent_rol_2.user_ids)
        assert_same_elements([@team.id], ent_rol_2.user_roles.where(actor_type: "Team").pluck(:actor_id))
      end
    end
  end
end
