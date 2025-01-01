# typed: true
# frozen_string_literal: true

require "test_helper"

class Notifications::OneClickUnsubscriptionsControllerTest < GitHub::IntegrationTestCase
  include NewsiesHelper

  fixtures do
    @user = create(:user)
    @repo = create :private_repository, owner: @user
    enable_notifications_for_user(@user, enabled_handlers: %w[web email])
    GitHub.newsies.subscribe_to_list(@user, @repo)

    @issue = perform_enqueued_jobs(only: [SubscribeAndNotifyJob]) do
      create(:issue, repository: @repo)
    end

    @summary = NotificationSummary.new(list: @repo, thread: @issue)
    @summary.rebuild_summary
    @summary.save!
  end

  test "POST /notifications/unsubscribe/one-click/:token fails if List-Unsubscribe param is missing" do
    token = GitHub.newsies.token :mute_list, @user, @summary[:id]

    refute GitHub.newsies.subscription_status(@user, @repo, @issue).ignored?

    post "/notifications/unsubscribe/one-click/#{token}"

    assert_response :bad_request
    refute GitHub.newsies.subscription_status(@user, @repo, @issue).ignored?
  end

  test "POST /notifications/unsubscribe/one-click/:token fails if is invalid" do
    post "/notifications/unsubscribe/one-click/ABC", params: { "List-Unsubscribe" => "One-Click" }

    assert_response :forbidden
  end

  test "POST /notifications/unsubscribe/one-click/:token unsubscribes from thread anonymously" do
    token = GitHub.newsies.token :mute_list, @user, @summary[:id]

    refute GitHub.newsies.subscription_status(@user, @repo, @issue).ignored?

    post "/notifications/unsubscribe/one-click/#{token}", params: { "List-Unsubscribe" => "One-Click" }

    assert_response :ok
    assert GitHub.newsies.subscription_status(@user, @repo, @issue).ignored?
  end

  test "POST /notifications/unsubscribe/one-click/:token unsubscribes from thread in notifyd", skip_enterprise: true do
    enable_feature_flag(:notifyd_enable_gist_thread_subscriptions, @user)

    gist = create(:gist)
    payload = { subject_type: "gist", topics: [{ type: "gist", value: gist.id.to_s }] }
    token = Notifyd::UnsubscribeToken.new(:mute_list).sign(@user, payload)

    post "/notifications/unsubscribe/one-click/#{token}", params: { "List-Unsubscribe" => "One-Click" }
    assert_response :ok
  end

  test "POST /notifications/unsubscribe/one-click/:token unsubscribes from member_feature_request", skip_enterprise: true do
    enable_feature_flag(:raf_email_notifications_notifyd, @user)

    member_feature_request_notification = create(:member_feature_request_notification, user: @user)
    payload = {
      subject_type: "MemberFeatureRequest::Notification",
      topics: [{
        type: "organization",
        value: member_feature_request_notification.entity_id
      }]
    }

    Notifyd::MemberFeatureRequestSettings.any_instance.expects(:save).returns(true)
    MemberFeatureRequest::Notification::Setting.any_instance.expects(:ignore!)

    token = Notifyd::UnsubscribeToken.new(:mute_list).sign(@user, payload)

    post "/notifications/unsubscribe/one-click/#{token}", params: { "List-Unsubscribe" => "One-Click" }
    assert_response :ok
  end

  test "POST /notifications/unsubscribe/one-click/:token unsubscribes from thread anonymously with EMUS", skip_enterprise: true do
    business = create(:business, :enterprise_managed)
    on_multi_tenant_enterprise(tenant: business) do
      user = create(:emu, business: business)
      owner = create(:organization, business: business, admin: user)

      repo = create(:repository, owner: owner)

      enable_notifications_for_user(user, enabled_handlers: %w[web email])
      GitHub.newsies.subscribe_to_list(user, repo)

      issue = perform_enqueued_jobs(only: [SubscribeAndNotifyJob]) do
        create(:issue, repository: repo)
      end

      summary = NotificationSummary.new(list: repo, thread: issue)
      summary.rebuild_summary
      summary.save!

      token = GitHub.newsies.token :mute_list, user, summary[:id]

      refute GitHub.newsies.subscription_status(user, repo, issue).ignored?

      post "/notifications/unsubscribe/one-click/#{token}", params: { "List-Unsubscribe" => "One-Click" }

      assert_response :ok
      assert GitHub.newsies.subscription_status(user, repo, issue).ignored?
    end
  end
end
