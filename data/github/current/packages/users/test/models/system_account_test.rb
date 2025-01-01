# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class SystemAccountTest < GitHub::TestCase
    test "knows that the ghost user is a system account" do
      user = create(:user)
      user.stubs ghost?: true
      assert user.system_account?, "Expected user #{user} to be a system account."
    end

    test "knows that the github-staff user is a system account" do
      user = User.staff_user
      assert user.system_account?, "Expected user #{user} to be a system account."
    end

    test "knows that the trusted_oauth_apps_org_name org is a system account" do
      make_trusted_oauth_apps_owner
      org = GitHub.trusted_oauth_apps_owner
      assert org.system_account?, "Expected org #{org} to be a system account."
    end

    test "knows that regular users/orgs are not system accounts" do
      user = create :user, login: :jdennes
      refute user.system_account?, "Expected user #{user} not to be a system account."

      org = create :organization, login: :rails
      refute org.system_account?, "Expected org #{org} not to be a system account."
    end
  end
end
