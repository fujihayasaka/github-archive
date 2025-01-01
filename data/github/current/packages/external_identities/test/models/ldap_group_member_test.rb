# typed: true
# frozen_string_literal: true

require "test_helper"

class LdapGroupMemberModelTest < GitHub::TestCase
  fixtures do
    @org  = create(:organization)
    @team = create(:team, organization: @org)

    @group_dn = "CN=AI Server R&D Group(C10D9169),OU=AI Server R&D Group,OU=Artificial Intelligence Team,OU=Next Generation Platform Center,OU=Mobile Communications Business,OU=IT & Mobile Communications,OU=CEO,OU=Github Electronics,OU=Employee,DC=corp,DC=github,DC=net"
    @member_dn = "uid=corywilkerson,ou=users,CN=AI Server R&D Group(C10D9169),OU=AI Server R&D Group,OU=Artificial Intelligence Team,OU=Next Generation Platform Center,OU=Mobile Communications Business,OU=IT & Mobile Communications,OU=CEO,OU=Github Electronics,OU=Employee,DC=corp,DC=github,DC=net"
  end

  test "requires a Team LdapMapping to persist" do
    mapping = @team.create_ldap_mapping(dn: "cn=LDAP,ou=teams,dc=github,dc=com")
    member  = mapping.group_cache_create_membership("uid=corywilkerson,ou=users,dc=github,dc=com")

    assert_predicate member.errors, :empty?, "Expected to be able to persist an LdapGroupMember with Team-based LdapMapping"
  end

  test "is invalid for a User LdapMapping" do
    user = create(:user, login: "corywilkerson")

    mapping = user.create_ldap_mapping(dn: "uid=corywilkerson,dc=github,dc=com")
    member  = mapping.group_cache_create_membership("uid=corywilkerson,ou=users,dc=github,dc=com")

    member.save

    assert_predicate member.errors, :any?, "We shouldn't be able to persist an LdapGroupMember with a User-based LdapMapping"
  end

  test "storing long group dn value works" do
    mapping = @team.create_ldap_mapping(dn: @group_dn)
    member  = mapping.group_cache_create_membership("uid=corywilkerson,ou=users,dc=github,dc=com")

    assert_predicate member.errors, :empty?, "Expected to be able to persist an LdapGroupMember with Team-based LdapMapping"
    assert_equal LdapMapping.hash_dn(@group_dn), member.group_dn
  end

  test "storing long member dn value works" do
    mapping = @team.create_ldap_mapping(dn: @group_dn)
    member  = mapping.group_cache_create_membership(@member_dn)

    assert_predicate member.errors, :empty?, "Expected to be able to persist an LdapGroupMember with Team-based LdapMapping"
    assert_equal LdapMapping.hash_dn(@member_dn), member.member_dn
  end
end
