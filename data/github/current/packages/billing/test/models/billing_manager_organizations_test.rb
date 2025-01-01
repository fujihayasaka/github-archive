# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class BillingManagerOrganizationsTest < GitHub::TestCase
    test "returns organizations that the user is a billing manager for" do
      user = create(:user)

      org = create(:organization)
      org.billing.add_manager(user, actor: org.admins.first)

      other_org = create(:organization)
      other_org.add_member(user)

      assert other_org.direct_or_team_member?(user)
      assert org.billing_manager?(user)

      assert_equal [org], user.billing_manager_organizations
    end

    test "does not return organizations that the user is a billing manager for if they have been soft-deleted" do
      user = create(:user)

      org = create(:organization)
      org.billing.add_manager(user, actor: org.admins.first)

      other_org = create(:organization)
      other_org.add_member(user)

      org.soft_delete!

      assert other_org.direct_or_team_member?(user)
      assert org.billing_manager?(user)

      assert_empty user.billing_manager_organizations
    end
  end
end
