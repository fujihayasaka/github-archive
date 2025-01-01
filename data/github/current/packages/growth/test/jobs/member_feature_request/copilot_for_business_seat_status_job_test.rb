# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class MemberFeatureRequest::CopilotForBusinessSeatStatusJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper

  fixtures do
    @user = create(:user)
    @organization = create(:organization)
    @organization.add_member(@user)
    @request = create(:member_feature_request, request_entity: @organization, requester: @user, feature: MemberFeatureRequest::Feature::CopilotForBusiness)
  end

  test "sets the status to fulfilled if the feature flag is enabled" do
    assert_difference(-> { MemberFeatureRequest.where(status: :fulfilled).count }, 1) do
      MemberFeatureRequest::CopilotForBusinessSeatStatusJob.perform_now(organization_id: @organization.id, user_id: @user.id)
    end
    assert @request.reload.fulfilled?
  end

  test "sets the status to fulfilled for matching request" do
    another_user = create(:user)
    @organization.add_member(another_user)
    another_request = create(:member_feature_request, request_entity: @organization, requester: another_user, feature: MemberFeatureRequest::Feature::CopilotForBusiness)

    assert_difference(-> { MemberFeatureRequest.where(status: :fulfilled).count }, 1) do
      MemberFeatureRequest::CopilotForBusinessSeatStatusJob.perform_now(organization_id: @organization.id, user_id: @user.id)
    end
    assert @request.reload.fulfilled?
    assert another_request.reload.requested?
  end

  test "does not set the status if there is no request for the user" do
    another_user = create(:user)
    @organization.add_member(another_user)

    assert_no_difference(-> { MemberFeatureRequest.where(status: :fulfilled).count }) do
      MemberFeatureRequest::CopilotForBusinessSeatStatusJob.perform_now(organization_id: @organization.id, user_id: another_user.id)
    end
    assert @request.reload.requested?
  end

  test "does not set the status if there is no request for the organization" do
    another_org = create(:organization)
    another_org.add_member(@user)

    assert_no_difference(-> { MemberFeatureRequest.where(status: :fulfilled).count }) do
      MemberFeatureRequest::CopilotForBusinessSeatStatusJob.perform_now(organization_id: another_org.id, user_id: @user.id)
    end
    assert @request.reload.requested?
  end

  test "does not set the status if there is no unfulfilled request" do
    @request.fulfilled!

    assert_no_difference(-> { MemberFeatureRequest.where(status: :fulfilled).count }) do
      assert_no_difference(-> { MemberFeatureRequest.where(status: :requested).count }) do
        MemberFeatureRequest::CopilotForBusinessSeatStatusJob.perform_now(organization_id: @organization.id, user_id: @user.id)
      end
    end
  end

  test "sets the status to fulfilled for CopilotForBusiness feature" do
    another_request = create(:member_feature_request, request_entity: @organization, requester: @user, feature: MemberFeatureRequest::Feature::DraftPullRequests)

    assert_difference(-> { MemberFeatureRequest.where(status: :fulfilled).count }, 1) do
      MemberFeatureRequest::CopilotForBusinessSeatStatusJob.perform_now(organization_id: @organization.id, user_id: @user.id)
    end
    assert @request.reload.fulfilled?
    assert another_request.reload.requested?
  end

  test "retries successfully" do
    assert_retry_conditions job: MemberFeatureRequest::CopilotForBusinessSeatStatusJob, args: [{ organization_id: @organization.id, user_id: @user.id }]
  end
end
