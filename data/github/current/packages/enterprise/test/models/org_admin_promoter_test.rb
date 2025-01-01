# typed: true
# frozen_string_literal: true

require "test_helper"

class OrgAdminPromoterTest < GitHub::TestCase

  fixtures do
    @non_staff = create(:user)

    @staff = create :staff_admin_user
    @org_a = create(:organization)
    @org_b = create(:organization)

    @admin = create :staff_admin_user
    @org_a.add_admin @admin
    @org_b.add_admin @admin

    assert @staff.site_admin?
  end

  if GitHub.enterprise?

    context "when a username is specified" do

      test "promotes a single staff user to admin on all orgs" do
        OrgAdminPromoter.new(username: @staff.login).run
        assert @org_a.adminable_by? @staff
        assert @org_b.adminable_by? @staff
      end

      test "does not promote a nonexistent user" do
        assert_raises OrgAdminPromoter::Error, /does not exist/ do
          OrgAdminPromoter.new(username: "i-made-this-all-up").run
        end
      end

      test "does not attempt to promote an organization" do
        assert_raises OrgAdminPromoter::Error, /is an organization/ do
          OrgAdminPromoter.new(username: @org_a.login).run
        end
      end

      test "does not promote a specified non-staff to admin" do
        assert_raises OrgAdminPromoter::Error, /site admin.*promote/ do
          OrgAdminPromoter.new(username: @non_staff.login).run
        end
        refute @org_a.adminable_by? @non_staff
        refute @org_b.adminable_by? @non_staff
      end

      test "does not promote a specified suspended user to admin" do
        @staff.suspend("because!")
        assert @staff.suspended?

        assert_raises OrgAdminPromoter::Error, /is suspended/ do
          OrgAdminPromoter.new(username: @staff.login).run
        end

        refute @org_a.adminable_by? @non_staff
        refute @org_b.adminable_by? @non_staff
      end

    end

    context "when no username is specified" do

      test "promotes all staff users to admin on all orgs" do
        OrgAdminPromoter.new(username: nil).run
        assert @org_a.adminable_by? @staff
        assert @org_b.adminable_by? @staff
      end

      test "does not promote non-staff users" do
        OrgAdminPromoter.new(username: nil).run
        refute @org_a.adminable_by? @non_staff
        refute @org_b.adminable_by? @non_staff
      end

      test "does not promote suspended staff" do
        @staff.suspend("because i said so")

        OrgAdminPromoter.new(username: nil).run

        refute @org_a.adminable_by? @staff
        refute @org_b.adminable_by? @staff
      end

    end

    context "when an organization is specified" do

      test "promotes all staff users to admin on an org" do
        OrgAdminPromoter.new(username: nil, organization: @org_a.login).run
        assert @org_a.adminable_by? @staff
        refute @org_b.adminable_by? @staff
      end

      test "does not promote all staff users to a non-existent org" do
        assert_raises OrgAdminPromoter::Error, /does not exist/ do
          OrgAdminPromoter.new(username: nil, organization: "i-made-this-all-up").run
        end
      end

    end

    context "when a username and an organization are specified" do

      test "promotes a single staff user to admin on an org" do
        OrgAdminPromoter.new(username: @staff.login, organization: @org_a.login).run
        assert @org_a.adminable_by? @staff
        refute @org_b.adminable_by? @staff
      end

      test "does not promote a user to a non-existent org" do
        assert_raises OrgAdminPromoter::Error, /does not exist/ do
          OrgAdminPromoter.new(username: @staff.login, organization: "i-made-this-all-up").run
        end
      end

      test "promotes a single non-staff user to admin on an org" do
        OrgAdminPromoter.new(username: @non_staff.login, organization: @org_a.login).run
        assert @org_a.adminable_by? @non_staff
        refute @org_b.adminable_by? @non_staff
      end

    end

    test "promotes staff members to org owners" do
      @org_a.add_member(@staff, action: :read)

      assert @org_a.direct_member?(@staff)

      OrgAdminPromoter.new(username: nil).run

      assert @org_a.adminable_by? @staff
      assert @org_b.adminable_by? @staff
    end

    test "does not promote non-staff members" do
      @org_a.add_member(@non_staff, action: :read)

      OrgAdminPromoter.new(username: nil).run

      refute @org_a.adminable_by? @non_staff
      refute @org_b.adminable_by? @non_staff
    end

    test "skips the github-enterprise organization entirely" do
      # Only create the "trusted" organization if it has not already been created by
      # another fixture (E.g. staff_admin_user)
      enterprise = Organization.find_by(login: "github-enterprise") || create(:organization, login: "github-enterprise")

      enterprise.legacy_owners_team.delete if enterprise.legacy_owners_team.present? # because it doesn't have one in production

      OrgAdminPromoter.new(username: @staff.login).run
      assert @org_a.adminable_by? @staff
      assert @org_b.adminable_by? @staff
      refute enterprise.adminable_by? @staff
    end

    test "does not add anyone without 2FA enabled to an org with 2FA required" do
      org_with_2fa = create :two_factor_credential_org
      site_admin_with_2fa = create :two_factor_credential_user
      site_admin_with_2fa.grant_site_admin_access "Reasons"

      OrgAdminPromoter.new(username: nil).run

      # @staff is only promoted to admin of orgs where 2FA not required
      assert @org_a.adminable_by? @staff
      assert @org_b.adminable_by? @staff
      refute org_with_2fa.two_factor_requirement_met_by? @staff
      refute org_with_2fa.adminable_by? @staff

      # site_admin_with_2fa is promoted to all orgs, including where 2FA required
      assert @org_a.adminable_by? site_admin_with_2fa
      assert @org_b.adminable_by? site_admin_with_2fa
      assert org_with_2fa.two_factor_requirement_met_by? site_admin_with_2fa
      assert org_with_2fa.adminable_by? site_admin_with_2fa
    end

  else # dotcom mode

    test "does not allow promotion of users in dotcom" do
      assert_raises OrgAdminPromoter::Error, /enterprise/ do
        OrgAdminPromoter.new(username: @staff.login).run
      end
    end
  end

end
