# typed: true
# frozen_string_literal: true

require "test_helper"

class LdapMappingModelTest < GitHub::TestCase
  fixtures do
    @map = create :user_ldap_mapping

    @org = create(:organization)
  end

  setup do
    @sync_error = GitHub::LDAP::UserSync::InvalidEmailError
  end

  test "human name for dn is LDAP DN" do
    mapping = LdapMapping.new
    mapping.valid?

    assert_includes mapping.errors.full_messages, "LDAP DN can't be blank"
  end

  test "can use the same dn for different teams mappings" do
    team1 = create(:team, organization: @org)
    team1.create_ldap_mapping(dn: "foo")

    team2 = create(:team, organization: @org)
    mapping = team2.create_ldap_mapping(dn: "foo")

    assert mapping.valid?, "Expected team to be valid with a duplicated ldap dn"
  end

  test "cannot use the same dn for different user mappings" do
    user = create(:user)
    user.create_ldap_mapping(dn: "foo")

    user2 = create(:user)
    mapping = user2.create_ldap_mapping(dn: "foo")

    refute mapping.valid?, "Expected user to not be valid with a duplicated ldap dn"
  end

  context "dn" do
    test "is hashed on creation" do
      team = create(:team, organization: @org)
      mapping = team.create_ldap_mapping(dn: "foo")

      assert_equal LdapMapping.hash_dn(mapping.dn), mapping.dn_hash
    end

    test "changes rehash the DN" do
      team = create(:team, organization: @org)
      mapping = team.create_ldap_mapping(dn: "foo")

      mapping.update dn: "bar"

      assert_equal LdapMapping.hash_dn("bar"), mapping.dn_hash
    end

    test "look up by hashed DN" do
      team = create(:team, organization: @org)
      mapping = team.create_ldap_mapping(dn: "foo")

      assert_equal mapping, LdapMapping.by_dn("foo").first
    end

    test "hashing is a SHA1 hash of the lowercase DN" do
      dn = "Test"
      assert_equal Digest::SHA1.hexdigest(dn.downcase), LdapMapping.hash_dn(dn) # rubocop:disable GitHub/InsecureHashAlgorithm
    end

    test "hashing ignores whitespace between RDNs" do
      dn = "uid=fry,ou=users,dc=github,dc=com"
      dn_with_spaces = "uid=fry, ou=users, dc=github, dc=com"

      assert_equal LdapMapping.hash_dn(dn), LdapMapping.hash_dn(dn_with_spaces)
    end

    test "hashing preserves whitespace inside RDN values" do
      dn_with_ignored_whitespace = "uid=Todd\\,Matt, ou=users, dc=github, dc=com"
      dn_with_preserved_whitespace = "uid=Todd\\, Matt, ou=users, dc=github, dc=com"

      refute_equal LdapMapping.hash_dn(dn_with_ignored_whitespace), LdapMapping.hash_dn(dn_with_preserved_whitespace)
    end
  end

  context "sync" do
    test "instruments when debug logging for LDAP is enabled" do
      events = subscribe "user.ldap_sync"
      GitHub::LDAP.stubs(:debug_logging_enabled?).returns(true)

      @map.sync do |payload|
        payload[:tested] = true
        payload[:ldap_fields_changed] = [:anything]
      end

      assert events.pop, "user.ldap_sync event expected when debug logging enabled"
    end

    test "instruments fields that changed during the LDAP sync" do
      events = subscribe "user.ldap_sync"
      GitHub::LDAP.stubs(:debug_logging_enabled?).returns(true)

      @map.sync do |payload|
        payload[:ldap_fields_changed] = [:anything]
      end

      assert event = events.pop, "user.ldap_sync event expected when debug logging enabled"
      assert_equal [:anything], event.payload[:ldap_fields_changed]
    end

    test "does not instrument when :ldap_fields_changed is empty" do
      events = subscribe "user.ldap_sync"

      @map.sync do |payload|
        payload[:ldap_fields_changed] = []
      end

      refute events.pop, "user.ldap_sync event not expected"
    end

    test "instruments failure" do
      events = subscribe "user.ldap_sync_error"

      assert_raises @sync_error do
        @map.sync do |payload|
          payload[:tested] = true
          raise @sync_error.new(@map.subject, mock, "invalid")
        end
      end

      assert event = events.pop, "user.ldap_sync_error event expected"
      assert event.payload[:tested], "should pass payload along for modification"
    end

    test "tracks syncing state" do
      @map.sync do
        assert_predicate @map, :syncing?
      end
    end

    test "tracks success state" do
      @map.sync {}
      assert_predicate @map, :synced?
    end

    test "tracks failure state" do
      assert_raises GitHub::LDAP::UserSync::InvalidEmailError do
        @map.sync do
          raise @sync_error.new(@map.subject, mock, "invalid")
        end
      end

      assert_predicate @map, :error?
    end

    test "tracks missing LDAP entry via raised error" do
      @map.sync do
        raise LdapMapping::MissingEntryError
      end

      assert_predicate @map, :gone?
    end

    test "add_runtime increases last_sync_ms" do
      @map.sync add_runtime: 50 do
        sleep 0.100
      end
      assert @map.last_sync_ms > (100 + 50)
    end
  end

  context "group cache" do
    test "group_cache_member? validates members backward compatibility without hash" do
      team = create(:team, organization: @org)
      mapping = team.create_ldap_mapping(dn: "cn=LDAP,ou=teams,dc=github,dc=com")

      member = "uid=mtodd,ou=users,dc=github,dc=com"

      refute mapping.group_cache_member?(member), "#{member} should not be in the group cache"

      mapping.ldap_group_members.create(member_dn: member)

      assert mapping.group_cache_member?(member), "#{member} should be in the group cache"
      assert_equal mapping.ldap_group_members.first.member_dn, member
    end

    test "group_cache_member? validates members set with group_cache_set_members" do
      team = create(:team, organization: @org)
      mapping = team.create_ldap_mapping(dn: "cn=LDAP,ou=teams,dc=github,dc=com")

      member = "uid=mtodd,ou=users,dc=github,dc=com"

      refute mapping.group_cache_member?(member), "#{member} should not be in the group cache"

      mapping.group_cache_set_members [member]

      assert mapping.group_cache_member?(member), "#{member} should be in the group cache"
      assert_equal mapping.ldap_group_members.first.member_dn, LdapMapping.hash_dn(member)
    end
  end
end
