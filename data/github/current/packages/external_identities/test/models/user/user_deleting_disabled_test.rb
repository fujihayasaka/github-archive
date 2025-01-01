# typed: true
# frozen_string_literal: true

require "test_helper"

class UserDeletingDisabledTest < GitHub::TestCase
  include AuthenticationHelpers::SAML

  context "enterprise environment" do
    test "returns true if GHES SCIM user" do
      setup_saml_auth_mode(with_scim: true)

      user = create :ghes_scim_user, :scim

      assert_predicate user, :managed_user_deletion_disabled?
    end
  end if GitHub.single_business_environment?

  test "returns false if GHES/GHEC user" do
    user = create :user

    refute_predicate user, :managed_user_deletion_disabled?
  end

  context "dotcom environment" do
    test "returns true if EMU user" do
      user = create :emu

      assert_predicate user, :managed_user_deletion_disabled?
    end
  end unless GitHub.single_business_environment?
end
