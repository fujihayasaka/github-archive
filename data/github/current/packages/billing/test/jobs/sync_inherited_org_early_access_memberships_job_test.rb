# typed: true
# frozen_string_literal: true

require "test_helper"

class SyncInheritedOrgEarlyAccessMembershipsJobTest < GitHub::TestCase
  include CopilotPublicUserCacheable

  setup do
    @copilot_code_review_beta = Copilot::CodeReviewBeta.new
    GitHub.flipper[:sync_inherited_org_early_access_memberships].enable
  end

  test "calls InheritOrgEarlyAccessJob when list of eligible org members do not match list of existing memberships" do
    org_membership = seed_org_membership
    org = org_membership.member

    new_member = create(:user, login: "newmember")
    org_membership.member.add_member(new_member)

    removed_member = org_membership.member.members.second
    removed_member_id = removed_member.id
    perform_enqueued_jobs(only: [RevokeOrgMembershipAbilitiesJob]) do
      org.remove_member!(removed_member)
    end

    assert_equal 3, EarlyAccessMembership.where(parent_id: org_membership.id, feature_slug: "copilot_code_review_public_preview").count
    refute_nil EarlyAccessMembership.find_by(parent_id: org_membership.id, member_id: removed_member_id, feature_slug: "copilot_code_review_public_preview")
    assert_nil EarlyAccessMembership.find_by(parent_id: org_membership.id, member_id: new_member.id, feature_slug: "copilot_code_review_public_preview")

    perform_enqueued_jobs(only: [InheritOrgEarlyAccessJob]) do
      SyncInheritedOrgEarlyAccessMembershipsJob.perform_now
    end

    assert_equal 2, EarlyAccessMembership.where(parent_id: org_membership.id, feature_slug: "copilot_code_review_public_preview").count
    # removed member
    assert_nil EarlyAccessMembership.find_by(parent_id: org_membership.id, member_id: removed_member_id, feature_slug: "copilot_code_review_public_preview")
    # added member, but no access to copilot
    assert_nil EarlyAccessMembership.find_by(parent_id: org_membership.id, member_id: new_member.id, feature_slug: "copilot_code_review_public_preview")

    # add copilot access to new member
    seat_assignment = create(:copilot_seat_assignment, organization: org, assignable: new_member)
    seat_assignment.convert_to_seats

    perform_enqueued_jobs(only: [InheritOrgEarlyAccessJob]) do
      SyncInheritedOrgEarlyAccessMembershipsJob.perform_now
    end

    refute_nil EarlyAccessMembership.find_by(parent_id: org_membership.id, member_id: new_member.id, feature_slug: "copilot_code_review_public_preview")
  end

  test "doesn't call InheritOrgEarlyAccessJob when list of eligible org members match a list of existing memberships" do
    seed_org_membership
    assert_enqueued_jobs(0, only: [InheritOrgEarlyAccessJob]) do
      SyncInheritedOrgEarlyAccessMembershipsJob.perform_now
    end
  end

  def seed_org_membership
    org_admin = create(:user)
    org = create(:organization, admins: [org_admin])
    user1 = create(:user)
    user2 = create(:user)
    user3 = create(:user)
    user_no_copilot = create(:user)

    Copilot::Organization.new(org).enable_copilot!

    [user1, user2, user3].each do |user|
      org.add_member(user)
      create(:copilot_seat_assignment, organization: org, assignable: user)
    end

    org.add_member(user_no_copilot)
    org_membership = EarlyAccessMembership.new(
      member: org,
      actor: org_admin,
      feature_slug: "copilot_code_review_public_preview",
      feature_enabled: true,
      survey: Copilot::CodeReviewBeta.new.survey
    )

    perform_enqueued_jobs(only: [InheritOrgEarlyAccessJob]) do
      org_membership.save!
    end

    org_membership
  end
end
