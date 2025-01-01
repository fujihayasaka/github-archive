# typed: true
# frozen_string_literal: true

require "test_helper"

class UserSCIMManagedTest < GitHub::TestCase
  include AuthenticationHelpers::SAML

  context "enterprise environment", enterprise_only: true do
    test "returns true if GHES SCIM user" do
      setup_saml_auth_mode(with_scim: true)

      user = create :ghes_scim_user, :scim

      assert_predicate user, :scim_managed_user?
    end
  end

  test "returns false if GHES/GHEC user" do
    user = create :user

    refute_predicate user, :scim_managed_user?
  end

  context "dotcom environment", skip_enterprise: true do
    test "returns true if emu user" do
      user = create :emu

      assert_predicate user, :scim_managed_user?
    end

    test "returns false if non emu user" do
      user = create :user

      refute_predicate user, :scim_managed_user?
    end
  end

  context "org always returns false" do
    test "GHES/GHEC org" do
      org = create :organization, admin: create(:user)

      refute_predicate org, :scim_managed_user?
    end

    test "emu org", skip_enterprise: true do
      user = create :emu, :owner
      org = create :organization, business: user.enterprise_managed_business, admin: user

      refute_predicate org, :scim_managed_user?
    end

    test "allow renaming if GHES SCIM org", enterprise_only: true do
      user = create :ghes_scim_user, :scim
      org = create :organization, business: GitHub.global_business, admin: user

      refute_predicate org, :scim_managed_user?
    end
  end
end
