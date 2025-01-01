# typed: true
# frozen_string_literal: true

require "test_helper"

class StafftoolsAccessControlTest < GitHub::TestCase
  fixtures do
    @staff = create :staff_admin_user
    @user  = create :user

    unless GitHub.enterprise?
      @business = create :business, :enterprise_managed
      @provider = create :business_saml_provider, business: @business
      @organization_admin = create :emu, business: @business
      @org = create :organization, business: @business, admin: @organization_admin
    end
  end

  setup do
    config = Psych.safe_load(File.read "#{Rails.root}/test/fixtures/stafftools_permissions.yml")
    Stafftools::AccessControl.stubs(:permissions).returns(config["permissions"])
  end

  context "GitHub Site permissions", skip_enterprise: true do
    test "non-staff user cannot access anything" do
      refute Stafftools::AccessControl.authorized?(
        @user, { controller: "Stafftools::UsersController", action: "index" })
    end

    context "staff user" do
      context "Controller level permission" do
        test "if no controller permissions exist, controller is open by default" do
          assert Stafftools::AccessControl.authorized?(
            @staff, { controller: "Stafftools::AssetsController", action: "index" })
        end

        test "opens all actions in controller to specified roles if action has no overrides" do
          @staff.stafftools_roles << StafftoolsRole.new(name: "super-admin")

          assert Stafftools::AccessControl.authorized?(
            @staff, { controller: "Stafftools::SearchIndexesController",
                    action: "index" })
        end

        test "users without access credentials cannot access the controller" do
          refute Stafftools::AccessControl.authorized?(
            @staff, { controller: "Stafftools::SearchIndexesController",
                    action: "index" })
        end

        test "* allows all users" do
          assert Stafftools::AccessControl.authorized?(
            @staff, { controller: "Stafftools::SessionsController",
                    action: "index" })
        end
      end

      context "action level permissions" do
        test "override, resets permissions" do
          refute Stafftools::AccessControl.authorized?(
            @staff, { controller: "Stafftools::SessionsController",
                    action: "impersonate" })

          @staff.stafftools_roles << StafftoolsRole.new(name: "support")

          assert Stafftools::AccessControl.authorized?(
            @staff, { controller: "Stafftools::SessionsController",
                    action: "impersonate" })
        end

        test "excluded roles" do
          @staff.stafftools_roles << StafftoolsRole.new(name: "read-only")

          refute Stafftools::AccessControl.authorized?(
            @staff, { controller: "Stafftools::UsersController",
                    action: "reindex" })

          @staff.stafftools_roles << StafftoolsRole.new(name: "support")

          assert Stafftools::AccessControl.authorized?(
            @staff, { controller: "Stafftools::UsersController",
                    action: "reindex" })
        end

        test "check to ensured allowed roles does not appear in action" do
          err = assert_raises Stafftools::AccessControl::RuleValidationError do
            Stafftools::AccessControl.authorized?(
              @staff, { controller: "Stafftools::ValidationErrorController", action: "index" })
          end

          assert_includes err.message, "cannot set allowed_roles please use allowed_roles_override"
        end

        test "check for only excluded or allowed roles override, not both" do
          err = assert_raises Stafftools::AccessControl::RuleValidationError do
            Stafftools::AccessControl.authorized?(
              @staff, { controller: "Stafftools::ValidationErrorController", action: "both" })
          end

          assert_includes err.message, "cannot set both allowed_roles and excluded_roles"
        end

        test "* allows all roles or no roles" do
          assert Stafftools::AccessControl.authorized?(
            @staff, { controller: "Stafftools::SearchIndexesController",
                    action: "open" })
        end
      end
    end
  end # End GitHub Site Permissions

  context "REST Api Permissions", skip_enterprise: true do
    test "non-staff user cannot access anything" do
      refute Stafftools::AccessControl.api_authorized?(
        @user, { route_pattern: "/staff/users", request_method: "get" })
    end

    context "Route pattern level" do
      test "if no route permissions exist, route is open by default" do
        assert Stafftools::AccessControl.api_authorized?(
          @staff, { route_pattern: "/staff/users", request_method: "get" })
      end

      test "opens all request methods for route to specified roles if method has no overrides" do
        @staff.stafftools_roles << StafftoolsRole.new(name: "super-admin")

        assert Stafftools::AccessControl.api_authorized?(
          @staff, { route_pattern: "/staff/admin_route",
                   request_method: "put" })
      end

      test "users without access credentials cannot access the route" do
        refute Stafftools::AccessControl.api_authorized?(
          @staff, { route_pattern: "/staff/admin_route",
                   request_method: "put" })
      end

      test "* allows all users" do
        assert Stafftools::AccessControl.api_authorized?(
          @staff, { route_pattern: "/staff/wildcard_route", request_method: "get" })
      end
    end

    context "request method (action) overides" do
      test "allows role override, resets permissions" do
        refute Stafftools::AccessControl.api_authorized?(
          @staff, { route_pattern: "/staff/override_route", request_method: "get" })

        @staff.stafftools_roles << StafftoolsRole.new(name: "support")

        assert Stafftools::AccessControl.api_authorized?(
          @staff, { route_pattern: "/staff/override_route",
                  request_method: "get" })
      end

      test "excluded roles" do
        @staff.stafftools_roles << StafftoolsRole.new(name: "read-only")

        refute Stafftools::AccessControl.api_authorized?(
          @staff, { route_pattern: "/staff/excluded_route",
                  request_method: "put" })

        @staff.stafftools_roles << StafftoolsRole.new(name: "support")

        assert Stafftools::AccessControl.api_authorized?(
          @staff, { route_pattern: "/staff/excluded_route",
                  request_method: "put" })
      end

      test "check to ensured allowed roles does not appear in action" do
        err = assert_raises Stafftools::AccessControl::RuleValidationError do
          Stafftools::AccessControl.api_authorized?(
            @staff, { route_pattern: "/staff/bad_access_configuration_route", request_method: "post" })
        end

        assert_includes err.message, "cannot set allowed_roles please use allowed_roles_override"
      end

      test "check for only excluded or allowed roles override, not both" do
        err = assert_raises Stafftools::AccessControl::RuleValidationError do
          Stafftools::AccessControl.api_authorized?(
            @staff, { route_pattern: "/staff/bad_access_configuration_route", request_method: "put" })
        end

        assert_includes err.message, "cannot set both allowed_roles and excluded_roles"
      end

      test "* allows all roles or no roles" do
        assert Stafftools::AccessControl.api_authorized?(
          @staff, { route_pattern: "/staff/admin_route", request_method: "get" })
      end
    end
  end

  context "GitHub Enterprise stafftools access controls", enterprise_only: true do
    test "non-staff are not authorized to access stafftools" do
      refute Stafftools::AccessControl.authorized?(
        @user, { controller: "Stafftools::UsersController", action: "index" })
    end

    test "restricted stafftools are accessible to all staff in Enterprise" do
      assert @staff.stafftools_roles.empty?
      assert Stafftools::AccessControl.authorized?(
        @staff, { controller: "Stafftools::SearchIndexesController", action: "index" })
    end

    test "non-staff are not authorized to access the stafftools API" do
      refute Stafftools::AccessControl.api_authorized?(
        @user, { route_pattern: "/staff/users", request_method: "get" })
    end

    test "restricted stafftools API routes are accessible to all staff in Enterprise" do
      assert @staff.stafftools_roles.empty?
      assert Stafftools::AccessControl.api_authorized?(
        @staff, { route_pattern: "/staff/admin_route", request_method: "put" })
    end
  end

  context "Stafftools role upgrades via external groups in multitenant", skip_enterprise: true do
    # update this test whenever new entries are made to the mapping yaml
    test "proxima_okta_map has the right count" do
      assert_equal 16, Stafftools::AccessControl.proxima_okta_map.count
    end

    test "upgrade returns nil when not multitenant" do
      assert_nil Stafftools::AccessControl.upgrade_stafftools_role_via_external_groups(@user)
    end

    test "upgrade returns nil when role is not defined" do
      on_multi_tenant_enterprise
      GitHub::CurrentTenant.stubs(:stafftools_tenant?).returns(true)
      GitHub::CurrentTenant.stubs(:get).returns(@business)
      assert_nil Stafftools::AccessControl.upgrade_stafftools_role_via_external_groups(@user)
    end

    test "upgrade user's stafftools role when external group membership is active" do
      on_multi_tenant_enterprise
      user = create :emu, business: @business

      GitHub::CurrentTenant.stubs(:stafftools_tenant?).returns(true)
      GitHub::CurrentTenant.stubs(:get).returns(@business)
      StafftoolsRole.create(name: "support")
      jit_group = create :external_group, business: @business, display_name: "stafftools-support-jit"
      support_jit_team = create :team, organization: @org
      # This simulates a SCIM API update to external groups
      ExternalGroupTeam.create(external_group: jit_group, team: support_jit_team)
      ExternalIdentityGroupMembership.create(external_group: jit_group, external_identity: user.external_identities.first)

      # test
      Stafftools::AccessControl.upgrade_stafftools_role_via_external_groups(user)

      # asserts
      user.reload
      assert_equal "staff", user.gh_role
      assert_equal "support", user.stafftools_roles.first.name
    end



    test "upgrade user's stafftools role when always-on external group membership is active" do
      on_multi_tenant_enterprise
      user = create :emu, business: @business

      GitHub::CurrentTenant.stubs(:stafftools_tenant?).returns(true)
      GitHub::CurrentTenant.stubs(:get).returns(@business)
      StafftoolsRole.create(name: "support")
      always_on_group = create :external_group, business: @business, display_name: "stafftools-support-always-on"
      support_jit_team = create :team, organization: @org
      # This simulates a SCIM API update to external groups
      ExternalGroupTeam.create(external_group: always_on_group, team: support_jit_team)
      ExternalIdentityGroupMembership.create(external_group: always_on_group, external_identity: user.external_identities.first)

      # test
      Stafftools::AccessControl.upgrade_stafftools_role_via_external_groups(user)

      # asserts
      user.reload
      assert_equal "staff", user.gh_role
      assert_equal "support", user.stafftools_roles.first.name
    end

    test "revoke user's stafftools roles when no external group membership is found" do
      on_multi_tenant_enterprise
      GitHub::CurrentTenant.stubs(:stafftools_tenant?).returns(true)
      GitHub::CurrentTenant.stubs(:get).returns(@business)
      _jit_group = create :external_group, business: @business, display_name: "#{@business.slug}-stafftools-developer-jit"
      _always_on_group = create :external_group, business: @business, display_name: "#{@business.slug}-stafftools-developer-always-on"
      #create a user with a stafftools role but no external group membership
      staff_user = create :emu, business: @business
      staff_user.gh_role = "staff"
      role = StafftoolsRole.create(name: "developer")
      staff_user.stafftools_roles << role
      staff_user.save!

      # test
      Stafftools::AccessControl.upgrade_stafftools_role_via_external_groups(staff_user)

      # asserts
      staff_user.reload
      refute_equal "staff", staff_user.gh_role
      assert_equal 0, staff_user.stafftools_roles.count
    end

    test "revoke user's staff role when access-jit exists but user is not a member" do
      on_multi_tenant_enterprise
      GitHub::CurrentTenant.stubs(:stafftools_tenant?).returns(true)
      GitHub::CurrentTenant.stubs(:get).returns(@business)
      jit_group = create :external_group, business: @business, display_name: "#{@business.slug}-stafftools-access-jit"
      always_on_group = create :external_group, business: @business, display_name: "#{@business.slug}-stafftools-developer-always-on"
      #create a user with a stafftools role but no external group membership
      staff_user = create :emu, business: @business
      staff_user.gh_role = "staff"
      staff_user.save!

      # test
      Stafftools::AccessControl.upgrade_stafftools_role_via_external_groups(staff_user)

      # asserts
      staff_user.reload
      refute_equal "staff", staff_user.gh_role
      assert_equal 0, staff_user.stafftools_roles.count
    end

    test "assign user's staff role when access-jit is enabled" do
      on_multi_tenant_enterprise
      GitHub::CurrentTenant.stubs(:stafftools_tenant?).returns(true)
      GitHub::CurrentTenant.stubs(:get).returns(@business)
      jit_group = create :external_group, business: @business, display_name: "#{@business.slug}-stafftools-access-jit"
      #create a user with a stafftools role but no external group membership
      staff_user = create :emu, business: @business
      ExternalIdentityGroupMembership.create(external_group: jit_group, external_identity: staff_user.external_identities.first)

      # test
      Stafftools::AccessControl.upgrade_stafftools_role_via_external_groups(staff_user)

      # asserts
      staff_user.reload
      assert_equal "staff", staff_user.gh_role
      assert_equal 0, staff_user.stafftools_roles.count
    end

    test "don't revoke user's staff role when access-jit is enabled" do
      on_multi_tenant_enterprise
      GitHub::CurrentTenant.stubs(:stafftools_tenant?).returns(true)
      GitHub::CurrentTenant.stubs(:get).returns(@business)
      access_jit_group = create :external_group, business: @business, display_name: "#{@business.slug}-stafftools-access-jit"
      _developer_jit_group = create :external_group, business: @business, display_name: "#{@business.slug}-stafftools-developer-jit"
      #create a user with a stafftools role but no external group membership
      staff_user = create :emu, business: @business
      staff_user.gh_role = "staff"
      role = StafftoolsRole.create(name: "developer")
      staff_user.stafftools_roles << role
      staff_user.save!
      ExternalIdentityGroupMembership.create(external_group: access_jit_group, external_identity: staff_user.external_identities.first)

      # test
      Stafftools::AccessControl.upgrade_stafftools_role_via_external_groups(staff_user)

      # asserts
      staff_user.reload
      assert_equal "staff", staff_user.gh_role
      assert_equal 0, staff_user.stafftools_roles.count
    end

    test "don't revoke user's staff role when always-on is enabled" do
      on_multi_tenant_enterprise
      GitHub::CurrentTenant.stubs(:stafftools_tenant?).returns(true)
      GitHub::CurrentTenant.stubs(:get).returns(@business)
      jit_group = create :external_group, business: @business, display_name: "#{@business.slug}-stafftools-access-always-on"
      #create a user with a stafftools role but no external group membership
      staff_user = create :emu, business: @business
      staff_user.gh_role = "staff"
      staff_user.save!
      ExternalIdentityGroupMembership.create(external_group: jit_group, external_identity: staff_user.external_identities.first)

      # test
      Stafftools::AccessControl.upgrade_stafftools_role_via_external_groups(staff_user)

      # asserts
      staff_user.reload
      assert_equal "staff", staff_user.gh_role
      assert_equal 0, staff_user.stafftools_roles.count
    end

    test "assign user's staff role when always-on is enabled" do
      on_multi_tenant_enterprise
      GitHub::CurrentTenant.stubs(:stafftools_tenant?).returns(true)
      GitHub::CurrentTenant.stubs(:get).returns(@business)
      jit_group = create :external_group, business: @business, display_name: "#{@business.slug}-stafftools-access-always-on"
      #create a user with a stafftools role but no external group membership
      staff_user = create :emu, business: @business
      ExternalIdentityGroupMembership.create(external_group: jit_group, external_identity: staff_user.external_identities.first)

      # test
      Stafftools::AccessControl.upgrade_stafftools_role_via_external_groups(staff_user)

      # asserts
      staff_user.reload
      assert_equal "staff", staff_user.gh_role
      assert_equal 0, staff_user.stafftools_roles.count
    end
  end
end
