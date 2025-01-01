# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class NotifydUnsubscribeFromLinkTest < GitHub::TestCase
    test "with a valid token" do
      user = create(:user)
      gist = create(:gist)
      payload = {
        subject_type: "gist",
        topics: [
          { type: "gist", value: gist.id.to_s }
        ],
      }
      action = :unsubscribe
      token = UnsubscribeToken.new(action).sign(user, payload)
      unsubscribe = UnsubscribeFromLink.new(action, token)

      auth, resource = unsubscribe.prepare

      assert_equal user, auth.user
      assert_predicate auth, :valid?
      assert_predicate auth.result, :success?
      assert_equal gist, resource.thread
      assert_predicate resource, :valid?
      refute_nil resource.permalink
    end

    test "finds an issue that has transfered" do
      user = create(:user)
      old_repository = create(:repository, owner: user)
      issue = create(:issue, repository: old_repository)
      payload = {
        subject_type: "issue",
        topics: [
          { type: "issue", value: issue.id.to_s }
        ],
      }
      action = :unsubscribe
      token = UnsubscribeToken.new(action).sign(user, payload)
      unsubscribe = UnsubscribeFromLink.new(action, token)

      new_repository = create(:repository, owner: user)
      transfer = IssueTransfer.new(old_issue: issue, old_repository: old_repository, new_repository: new_repository, actor: user)
      transfer.transfer!
      transfer.save!

      auth, resource = unsubscribe.prepare

      assert_equal user, auth.user
      assert_predicate auth, :valid?
      assert_predicate auth.result, :success?
      assert_equal issue.title, resource.thread.title
      refute_nil resource.permalink
    end

    test "does not find an issue that has been deleted" do
      user = create(:user)
      issue = create(:issue)
      payload = {
        subject_type: "issue",
        topics: [
          { type: "issue", value: issue.id.to_s }
        ],
      }
      action = :unsubscribe
      token = UnsubscribeToken.new(action).sign(user, payload)
      unsubscribe = UnsubscribeFromLink.new(action, token)

      auth, resource = unsubscribe.prepare

      issue.destroy!

      assert_equal user, auth.user
      assert_predicate auth, :valid?
      assert_predicate auth.result, :success?
      assert_nil resource.thread
      refute_predicate resource, :valid?
      assert_nil resource.permalink
    end

    test "with an invalid payload" do
      user = create(:user)
      gist = create(:gist)
      payload = {}
      action = :unsubscribe
      token = UnsubscribeToken.new(action).sign(user, payload)
      unsubscribe = UnsubscribeFromLink.new(action, token)

      auth, resource = unsubscribe.prepare

      assert_equal user, auth.user
      assert_predicate auth, :valid?
      assert_predicate auth.result, :success?
      assert_nil resource.thread
      refute_predicate resource, :valid?
      assert_nil resource.permalink
    end

    test "with an invalid token" do
      action = :unsubscribe
      token = "foo"

      unsubscribe = UnsubscribeFromLink.new(action, token)
      auth, resource = unsubscribe.prepare

      refute_predicate auth, :valid?
      assert_predicate auth.result, :success?
      assert_nil resource.thread
      refute_predicate resource, :valid?
      assert_nil auth.user
      assert_nil resource.permalink
    end

    test "uses the MemberFeatureRequestResource" do
      user = create(:user)
      member_feature_request_notification = create(:member_feature_request_notification, user: user)
      payload = {
        subject_type: "MemberFeatureRequest::Notification",
        topics: [{
          type: "organization",
          value: member_feature_request_notification.entity_id
        }]
      }
      action = :unsubscribe
      token = UnsubscribeToken.new(action).sign(user, payload)
      unsubscribe = UnsubscribeFromLink.new(action, token)

      auth, resource = unsubscribe.prepare

      assert_equal user, auth.user
      assert_predicate auth, :valid?
      assert_predicate auth.result, :success?
      assert_predicate resource, :valid?
      assert_equal "MemberFeatureRequest::Notification", resource.subject_type
      assert_equal member_feature_request_notification.entity_id, resource.organization_id
      assert_match "/settings/member_feature_requests", resource.permalink
    end
  end
end
