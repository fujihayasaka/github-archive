# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationTheTrustedAppsOwnerTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @staffer = create(:staff_admin_user)
    @org  = make_trusted_oauth_apps_owner
    @org.add_admin(@user)
    @org2 = create(:organization, admin: @user, plan: "bronze")
    @spammyorg = create(:organization, admin: @user, plan: "bronze", spammy: true)
  end

  test "it cannot be destroyed" do
    assert !@org.destroy, "Expected org to not be destroyed."
  end

  unless GitHub.enterprise?
    test "spammy org cannot be destroyed by user" do
      refute @spammyorg.permit_deletion?(@user), "Spammy org cannot be deleted by user."
    end
  end

  test "spammy org can be destroyed by a staffer" do
    assert @spammyorg.permit_deletion?(@staffer), "Spammy org should be only deleted by staff."
  end

  test "there is only one trusted owner" do
    assert @org.trusted_oauth_apps_owner?, "Expected org #{@org} to be the trusted oauth owner."
    assert !@org2.trusted_oauth_apps_owner?, "Expected org #{@org2} to not be the trusted oauth owner."
  end
end
