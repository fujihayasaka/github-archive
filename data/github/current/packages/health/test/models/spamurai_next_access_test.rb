# typed: true
# frozen_string_literal: true

require "test_helper"

class SpamuraiNextAccessTest < GitHub::TestCase
  context "user_has_permission?" do
    test "returns true if the permission cache has this user" do
      permission = "some-permission"
      users = %w[user1 user2]
      SpamuraiNextAccess.cache_users_with_permission(permission, users)
      SpamuraiNextAccess.expects(:users_with_permission).never
      assert SpamuraiNextAccess.user_has_permission?(login: "user1", permission: permission)
      assert SpamuraiNextAccess.user_has_permission?(login: "user2", permission: permission)
    end

    test "uses entitlements to know if a user has a permission if we don't have it cached" do
      permission = "some-permission"
      users = %w[user1 user2]
      SpamuraiNextAccess.expects(:users_with_permission).times(3).returns(users)
      assert SpamuraiNextAccess.user_has_permission?(login: "user1", permission: permission)
      Spam::Kv.store.del(SpamuraiNextAccess.permission_cache_key(permission))
      assert SpamuraiNextAccess.user_has_permission?(login: "user2", permission: permission)
      Spam::Kv.store.del(SpamuraiNextAccess.permission_cache_key(permission))
      refute SpamuraiNextAccess.user_has_permission?(login: "user3", permission: permission)
    end

    test "handles capitalized logins" do
      permission = "some-permission"
      users = %w[user1]
      SpamuraiNextAccess.expects(:users_with_permission).returns(users.map(&:downcase))
      assert SpamuraiNextAccess.user_has_permission?(login: "User1", permission: permission)
    end

    test "is always true for hubot" do
      permission = "some-permission"
      SpamuraiNextAccess.expects(:cached_users_with_permission).never
      SpamuraiNextAccess.expects(:users_with_permission).never
      assert SpamuraiNextAccess.user_has_permission?(login: "hubot", permission: permission)
    end
  end

  context "users_with_permission" do
    test "searches LDAP for users with a permission and returns their logins" do
      permission = "actions-classify-spammy"
      dn = "cn=actions-classify-spammy,ou=spamurai-next-access,ou=Apps,ou=Entitlements,ou=Groups,dc=github,dc=net"
      entry = Net::LDAP::Entry.new(dn)
      entry[:description] = "Spamurai Next classify-spammy action access"
      entry[:owner] = "uid=entitlements,ou=Service_Accounts,dc=github,dc=net"
      entry[:objectclass] = "groupOfUniqueNames"
      entry[:cn] = "actions-classify-spammy"
      entry[:uniquemember] = [
        "uid=user1,ou=People,dc=github,dc=net",
        "uid=user2,ou=People,dc=github,dc=net",
      ]

      ldap_client = {}
      GitHub.stubs(:platform_health_entitlements_ldap_client).returns(ldap_client)
      ldap_client.expects(:search).with(
        base: "cn=actions-classify-spammy,ou=spamurai-next-access,ou=Apps,ou=Entitlements,ou=Groups,dc=github,dc=net",
        attrs: %w[uniquemember],
        scope: Net::LDAP::SearchScope_BaseObject,
      ).yields(entry)
      users = SpamuraiNextAccess.users_with_permission(permission)
      assert_equal %w[user1 user2], users
    end
  end
end
