# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class MemberFeatureRequest::SyncCopilotForBusinessSeatStatusJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @organization = create(:organization)

    @user1 = create(:user)
    @organization.add_member(@user1)
    @feature_request1 = create(:member_feature_request, request_entity: @organization, requester: @user1, feature: MemberFeatureRequest::Feature::CopilotForBusiness)

    @user2 = create(:user)
    @organization.add_member(@user2)
    @feature_request2 = create(:member_feature_request, request_entity: @organization, requester: @user2, feature: MemberFeatureRequest::Feature::CopilotForBusiness)
  end

  test "next_batch includes all MemberFeatureRequests with CopilotForBusiness feature and requested status" do
    batch = MemberFeatureRequest::SyncCopilotForBusinessSeatStatusJob.new.next_batch

    assert_includes batch, @feature_request1
    assert_includes batch, @feature_request2
  end

  test "next_batch includes only MemberFeatureRequests with CopilotForBusiness feature" do
    @feature_request2.update(feature: MemberFeatureRequest::Feature::ProtectedBranches)

    batch = MemberFeatureRequest::SyncCopilotForBusinessSeatStatusJob.new.next_batch

    assert_includes batch, @feature_request1
    refute_includes batch, @feature_request2
  end

  test "next_batch includes only MemberFeatureRequests with requested status" do
    @feature_request2.fulfilled!

    batch = MemberFeatureRequest::SyncCopilotForBusinessSeatStatusJob.new.next_batch

    assert_includes batch, @feature_request1
    refute_includes batch, @feature_request2
  end

  test "enqueues CopilotForBusinessSeatStatusJob for request with assigned copilot seats" do
    create(:copilot_seat, assigned_user: @feature_request1.requester, organization: @feature_request1.organization)

    assert_enqueued_jobs 1, only: MemberFeatureRequest::CopilotForBusinessSeatStatusJob do
      assert_enqueued_with(job: MemberFeatureRequest::CopilotForBusinessSeatStatusJob, args: [{ organization_id: @feature_request1.organization_id, user_id: @feature_request1.requester_id }]) do
        MemberFeatureRequest::SyncCopilotForBusinessSeatStatusJob.perform_now
      end
    end
  end
end
