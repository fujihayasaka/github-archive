# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.enterprise?
  class ExternalAccountSuspensionTest < GitHub::TestCase
    include AuthenticationHelpers::LDAP

    fixtures do
      @user = create(:user)
    end

    test "is false when auth mode is not LDAP" do
      refute GitHub.auth.ldap?, "LDAP auth mode not expected"

      LdapMapping.any_instance.expects(:entry).never

      @user.map_ldap_entry("uid=user1,ou=users,dc=ad,dc=github,dc=com")
      refute_predicate @user, :ldap_mapped?

      refute_predicate @user, :external_account_suspension?
    end

    context "without Active Directory" do
      test "is false when auth mode is LDAP but LDAP sync isn't enabled" do
        with_auth_mode(:ldap) do
          assert GitHub.auth.ldap?, "LDAP auth mode expected"
          refute GitHub.ldap_sync_enabled?, "LDAP Sync should be disabled"

          # mock out entry that is not from Active Directory
          entry = Net::LDAP::Entry.new "uid=user1,ou=users,dc=openldap,dc=github,dc=com"
          LdapMapping.any_instance.stubs(:entry).returns(entry)

          @user.map_ldap_entry("uid=user1,ou=users,dc=openldap,dc=github,dc=com")
          assert_predicate @user, :ldap_mapped?

          refute_predicate @user, :external_account_suspension?
        end
      end
    end

    context "with Active Directory" do
      test "is false when auth mode is LDAP but LDAP sync isn't enabled" do
        with_auth_mode(:ldap) do
          assert GitHub.auth.ldap?, "LDAP auth mode expected"
          refute GitHub.ldap_sync_enabled?, "LDAP Sync should be disabled"

          # mock out attribute Active Directory would return
          entry = Net::LDAP::Entry.new "uid=user1,ou=users,dc=ad,dc=github,dc=com"
          entry["userAccountControl"] = 0
          LdapMapping.any_instance.stubs(:entry).returns(entry)

          @user.map_ldap_entry("uid=user1,ou=users,dc=ad,dc=github,dc=com")
          assert_predicate @user, :ldap_mapped?

          refute_predicate @user, :external_account_suspension?
        end
      end
    end

    ldap_test "is false if not mapped to an LDAP user" do
      refute_predicate @user, :external_account_suspension?
    end

    ldap_test "is false when not active directory" do
      @user.map_ldap_entry("uid=user1,ou=users,dc=ad,dc=github,dc=com")

      entry = Net::LDAP::Entry.new "uid=jch,ou=users,dc=github,dc=com"
      LdapMapping.any_instance.stubs(:entry).returns(entry)

      refute_predicate @user, :external_account_suspension?
    end

    ldap_test "is true with ldap sync and active directory" do
      assert GitHub.auth.ldap?, "LDAP auth mode expected"
      assert GitHub.ldap_sync_enabled?, "LDAP Sync should be enabled"

      @user.map_ldap_entry("uid=user1,ou=users,dc=ad,dc=github,dc=com")

      # mock out attribute Active Directory would return
      entry = Net::LDAP::Entry.new "uid=user1,ou=users,dc=ad,dc=github,dc=com"
      entry["userAccountControl"] = 0
      LdapMapping.any_instance.stubs(:entry).returns(entry)

      assert_predicate @user, :external_account_suspension?
    end

    ldap_test "is false when mapped LDAP entry cannot be loaded" do
      @user.map_ldap_entry("uid=user1,ou=users,dc=ad,dc=github,dc=com")

      # This occurs if the user DN is modified and the entry can no longer be
      # loaded, or if the entry is moved in LDAP. LdapMapping#entry returns nil,
      # causing an exception when trying to load attributes on the entry.
      LdapMapping.any_instance.stubs(:entry).returns(nil)

      refute_predicate @user, :external_account_suspension?
    end

    ldap_test "is false if LDAP server is unreachable" do
      @user.map_ldap_entry("uid=user1,ou=users,dc=ad,dc=github,dc=com")
      LdapMapping.any_instance.stubs(:entry).raises(Net::LDAP::Error)

      refute_predicate @user, :external_account_suspension?
    end

    # These ensure we can still un/suspend the user internally via UserSync.

    test "suspend succeeds" do
      @user.stubs(:external_account_suspension?).returns(true)
      assert @user.suspend("reason")
      assert_predicate @user, :suspended?
    end

    test "unsuspend succeeds" do
      @user.suspend("testing")
      assert_predicate @user, :suspended?

      @user.stubs(:external_account_suspension?).returns(true)

      assert @user.unsuspend("reason")
      refute_predicate @user, :suspended?
    end
  end
end
