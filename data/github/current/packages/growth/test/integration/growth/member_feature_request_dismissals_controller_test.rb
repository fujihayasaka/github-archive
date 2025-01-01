# typed: true
# frozen_string_literal: true

require "test_helper"

module Growth
  class MemberFeatureRequestDismissalsControllerTest < GitHub::IntegrationTestCase
    include ActionMailer::TestHelper

    fixtures do
      @user = create(:user)
      @admin = create(:user)
      @organization = create(:organization, admin: @admin)
      @organization.add_member(@user)
      @member_feature_request = create(:member_feature_request, status: :requested, request_entity: @organization, requester: @user)
    end

    test "should dismiss member feature request" do
      as @admin
      assert @member_feature_request.requested?
      assert_enqueued_email_with(MemberFeatureRequestMailer, :notify_dismissal, args: @member_feature_request) do
        patch "/growth/member_feature_request_dismissals/#{@member_feature_request.id}"
      end
      assert_response :ok
      @member_feature_request.reload
      assert @member_feature_request.dismissed?
      assert_equal @admin, @member_feature_request.dismissed_by
    end

    test "should return not found when member feature request does not exist" do
      as @admin
      patch "/growth/member_feature_request_dismissals/#{MemberFeatureRequest.last.id + 1}", as: :json
      assert_response :not_found
    end

    test "should return service unavailable when ActiveRecord::ActiveRecordError is raised" do
      MemberFeatureRequest.any_instance.expects(:dismiss_request!).raises(ActiveRecord::ActiveRecordError)
      as @admin
      patch("/growth/member_feature_request_dismissals/#{@member_feature_request.id}", format: :json)
      assert_response :service_unavailable
    end

    test "should return forbidden if user is not an admin of the organization" do
      member = create(:user)
      @organization.add_member(member)

      as member
      patch("/growth/member_feature_request_dismissals/#{@member_feature_request.id}", format: :json)

      assert_response :forbidden
    end
  end
end
