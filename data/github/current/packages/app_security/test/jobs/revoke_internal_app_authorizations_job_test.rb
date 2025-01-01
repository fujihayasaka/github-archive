# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RevokeInternalAppAuthorizationsJobTest < GitHub::TestCase
  include JobTestHelper

  test "destroys internal-app OAuth authorizations for an enterprise member" do
    member = create(:user)
    app = create(:enterprise_owned_integration)
    business = app.owner
    org = create(:organization, business: business)
    org.add_member(member)
    assert business.async_member?(member).sync, "#{member} should be a member of #{business}"

    oauth_access = app.grant(member)
    assert_equal 1, app.accesses.count
    assert_equal 1, app.authorizations.count

    assert_changes "OauthAuthorization.count", -1 do
      assert_changes "OauthAccess.count", -1 do
        RevokeInternalAppAuthorizationsJob.perform_now(enterprise_id: business.id, user_ids: [member.id])
      end
    end

    assert_equal 0, app.accesses.count
    assert_equal 0, app.authorizations.count
  end

  test "destroys authorizations for internal apps for enterprise-owned organization member" do
    member = create(:user)
    app = create(:enterprise_owned_integration)
    business = app.owner
    org = create(:organization, business: business)
    org.add_member(member)
    assert business.async_member?(member).sync, "#{member} should be a member of #{business}"

    oauth_access = app.grant(member)
    assert_equal 1, app.accesses.count
    assert_equal 1, app.authorizations.count

    assert_changes "OauthAuthorization.count", -1 do
      assert_changes "OauthAccess.count", -1 do
        RevokeInternalAppAuthorizationsJob.perform_now(organization_id: org.id, user_ids: [member.id])
      end
    end

    assert_equal 0, app.accesses.count
    assert_equal 0, app.authorizations.count
  end

  test "destroys authorizations for all internal apps owned by the enterprise" do
    member = create(:user)
    app_one = create(:enterprise_owned_integration)
    business = app_one.owner
    app_two = create(:enterprise_owned_integration, owner: business)
    org = create(:organization, business: business)
    org.add_member(member)
    assert business.async_member?(member).sync, "#{member} should be a member of #{business}"

    oauth_access = app_one.grant(member)
    oauth_access = app_two.grant(member)
    assert_equal 1, app_one.accesses.count
    assert_equal 1, app_two.accesses.count
    assert_equal 1, app_one.authorizations.count
    assert_equal 1, app_two.authorizations.count

    assert_changes "OauthAuthorization.count", -2 do
      assert_changes "OauthAccess.count", -2 do
        RevokeInternalAppAuthorizationsJob.perform_now(enterprise_id: business.id, user_ids: [member.id])
      end
    end

    assert_equal 0, app_one.accesses.count
    assert_equal 0, app_two.accesses.count
    assert_equal 0, app_one.authorizations.count
    assert_equal 0, app_two.authorizations.count
  end

  test "destroys authorizations for all internal apps authorized by all removed users" do
    member_one = create(:user)
    member_two = create(:user)

    app_one = create(:enterprise_owned_integration)
    business = app_one.owner

    app_two = create(:enterprise_owned_integration, owner: business)

    org = create(:organization, business: business)
    org.add_member(member_one)
    org.add_member(member_two)
    assert business.async_member?(member_one).sync, "#{member_one} should be a member of #{business}"
    assert business.async_member?(member_two).sync, "#{member_two} should be a member of #{business}"

    oauth_access = app_one.grant(member_one)
    oauth_access = app_two.grant(member_two)
    assert_equal 1, app_one.accesses.count
    assert_equal 1, app_two.accesses.count
    assert_equal 1, app_one.authorizations.count
    assert_equal 1, app_two.authorizations.count

    assert_changes "OauthAuthorization.count", -2 do
      assert_changes "OauthAccess.count", -2 do
        RevokeInternalAppAuthorizationsJob.perform_now(enterprise_id: business.id, user_ids: [member_one.id, member_two.id])
      end
    end

    assert_equal 0, app_one.accesses.count
    assert_equal 0, app_two.accesses.count
    assert_equal 0, app_one.authorizations.count
    assert_equal 0, app_two.authorizations.count
  end

  # There can only be multiple enterprises in *non* EMU/Enterprise/Multitenant
  # modes, so this test doesn't work there because it's impossible to create an
  # internal-visibility app outside of the main enterprise.
  test "only destroys authorizations for apps owned by the given enterprise", skip_with_all_emus: true, skip_in_multitenant_mode: true, skip_enterprise: true do
    member = create(:user)
    app = create(:enterprise_owned_integration)
    business = app.owner
    org = create(:organization, business: business)
    org.add_member(member)
    assert business.async_member?(member).sync, "#{member} should be a member of #{business}"

    other_app = create(:enterprise_owned_integration)
    refute_equal business, other_app.owner

    app.grant(member)
    other_app.grant(member)
    assert_equal 1, app.accesses.count
    assert_equal 1, app.authorizations.count
    assert_equal 1, other_app.accesses.count
    assert_equal 1, other_app.authorizations.count

    assert_changes "OauthAuthorization.count", -1 do
      assert_changes "OauthAccess.count", -1 do
        RevokeInternalAppAuthorizationsJob.perform_now(enterprise_id: business.id, user_ids: [member.id])
      end
    end

    assert_equal 0, app.accesses.count
    assert_equal 0, app.accesses.count
    assert_equal 1, other_app.authorizations.count
    assert_equal 1, other_app.authorizations.count
  end

  # Can't have standalone organizations (no owning enterprise) outside of
  # GHEC on Dotcom.
  test "does nothing for organizations that are not part of an enterprise", skip_with_all_emus: true, skip_in_multitenant_mode: true, skip_enterprise: true do
    member = create(:user)
    org = create(:organization)
    app = create(:integration, owner: org)
    org.add_member(member)

    oauth_access = app.grant(member)
    assert_equal 1, app.accesses.count
    assert_equal 1, app.authorizations.count

    assert_no_changes "OauthAuthorization.count" do
      assert_no_changes "OauthAccess.count" do
        RevokeInternalAppAuthorizationsJob.perform_now(organization_id: org.id, user_ids: [member.id])
      end
    end

    assert_equal 1, app.accesses.count
    assert_equal 1, app.authorizations.count
  end
end
