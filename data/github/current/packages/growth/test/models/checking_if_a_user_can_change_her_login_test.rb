# typed: true
# frozen_string_literal: true

require "test_helper"

class CheckingIfAUserCanChangeHerLoginTest < GitHub::TestCase
  include AuthenticationHelpers::LDAP

  fixtures do
    @user = create(:user)
  end

  test "can change logins with the default auth" do
    assert @user.renaming_enabled?
  end

  test "cannot change login with one if the omniauth adapters" do
    with_auth_mode(:cas) do
      refute @user.renaming_enabled?
    end

    with_auth_mode(:github_oauth) do
      refute @user.renaming_enabled?
    end
  end

  ldap_test "cannot change login with ldap and no mapping" do
    refute @user.renaming_enabled?
  end

  ldap_test "can change login with ldap and external mapping" do
    @user.build_ldap_mapping(dn: "uid=calavera,dc=github,dc=com")
    assert @user.renaming_enabled?
  end
end
