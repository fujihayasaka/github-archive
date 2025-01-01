# typed: true
# frozen_string_literal: true

require "test_helper"

module OnboardingTasks
  module Organizations
    class OrganizationsInviteMemberTest < GitHub::TestCase
      fixtures do
        @owner = create(:user)
        @org = create(:organization, admin: @owner)
      end

      context  "verify_task" do
        test "returns false when there is no member or invite" do
          refute InviteMember.new(taskable: @org, user: @owner).verify_task
        end

        test "returns true if there is a pending invitation" do
          create(:organization_invitation, organization: @org)

          assert InviteMember.new(taskable: @org, user: @owner).verify_task
        end

        test "returns true if the invitation was accepted" do
          invitation = create(:organization_invitation, organization: @org)
          invitation.accept

          assert InviteMember.new(taskable: @org, user: @owner).verify_task
        end
      end
    end
  end
end
