# typed: true
# frozen_string_literal: true

require "test_helper"

class SyncSiteAdminAndGlobalBusinessAdminTest < GitHub::TestCase
  fixtures do
    # Ensure there's a global business created
    create :business
  end

  if GitHub.single_business_environment?
    test "promotes created site admins as global business admins" do
      user = create :staff_admin_user
      assert user.site_admin?
      assert GitHub.global_business.owner?(user)
    end

    test "users promoted as site admins are also promoted as global business admins" do
      user = create :user
      user.grant_site_admin_access "Reasons"
      assert user.site_admin?
      assert GitHub.global_business.owner?(user)
    end

    test "doesn't blow up on saving org that was previously a site admin user then transformed to org" do
      user = create :staff_admin_user, login: "to-be-transformed-into-org"
      assert user.site_admin?
      assert GitHub.global_business.owner?(user)

      Organization.transform!(user, create(:user))
      org = Organization.find_by login: "to-be-transformed-into-org"
      T.must(org).description = "Was previously a site admin user"
      T.must(org).save!
    end

    test "users demoted from site admin are also demoted from global business admin (but are not notified)" do
      user = create :staff_admin_user
      assert GitHub.global_business.owner?(user)

      BusinessMailer.expects(:removed_as_business_admin).never
      user.revoke_privileged_access "Reasons"
      refute GitHub.global_business.owner?(user)
    end
  else
    test "is a no-op when not in a single global business env" do
      create :staff_admin_user
      assert_nil GitHub.global_business
    end
  end
end
