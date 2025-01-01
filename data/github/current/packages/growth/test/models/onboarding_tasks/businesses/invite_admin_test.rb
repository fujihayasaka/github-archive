# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

module OnboardingTasks
  module Businesses
    class InviteAdminTest < GitHub::TestCase
      fixtures do
        @owner = create(:user)
        @admin = create(:user)
        @business = create(:business, owners: [@owner])
      end

      context  "verify_task" do
        test "returns false if no admin invitations" do
          @business.invitations.destroy_all

          assert_equal false, InviteAdmin.new(taskable: @business, user: @owner).verify_task
        end

        test "returns true if there are admin invitations" do
          @business.invite_admin(user: @admin, inviter: @owner, role: Business::OWNER_ROLE)

          assert_equal true, InviteAdmin.new(taskable: @business, user: @owner).verify_task
        end
      end
    end
  end
end
