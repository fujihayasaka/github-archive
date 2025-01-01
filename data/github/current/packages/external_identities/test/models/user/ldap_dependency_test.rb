# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.enterprise?
  class UserWithLdapDependencyTest < GitHub::TestCase
    include AuthenticationHelpers::LDAP

    fixtures do
      @user = create(:user, ldap_mapping: LdapMapping.new(dn: "foo"))
    end

    test "destroys users' ldap mappings" do
      assert_difference("LdapMapping.count", -1) do
        @user.destroy
      end
    end

    ldap_test "force ldap membership sync" do
      @user.update!(needs_ldap_memberships_sync: true)

      assert @user.sync_ldap_memberships?,
        "Expected ldap membership sync to not be ignored"
    end

    test "ignore ldap memberships sync when ldap is not enabled" do
      refute @user.sync_ldap_memberships?,
        "Expected ldap membership sync to be ignored"
    end

    test "ignore ldap memberships sync when they have been already synced" do
      @user.ldap_memberships_synced!

      refute @user.sync_ldap_memberships?,
        "Expected ldap membership sync to be ignored"
    end

    ldap_test "returns teams from any organization when the sync is in progress" do
      team = create(:team)
      team2 = create(:team)
      team.add_member @user
      team2.add_member @user

      assert_equal 2, @user.teams.size
    end

    ldap_test "returns teams from any organization when there is no sync in progress" do
      team = create(:team)
      team2 = create(:team)
      team.add_member @user
      team2.add_member @user
      assert_equal 2, @user.teams.size
    end
  end
else
  class UserWithoutLdapDependencyTest < GitHub::TestCase
    fixtures do
      @user = create(:user)
    end

    test "ignore ldap memberships sync" do
      refute @user.sync_ldap_memberships?,
        "Expected ldap membership sync to be ignored"
    end
  end
end
