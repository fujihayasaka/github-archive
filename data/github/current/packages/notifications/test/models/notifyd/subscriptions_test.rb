# typed: true
# frozen_string_literal: true

require "test_helper"

class NotifydSubscriptionsTest < GitHub::TestCase
  include NotifydTestHelper
  RS = Notifyd::Proto::RoutingSettings
  Subs = Notifyd::Proto::Subscriptions

  class NonSubscribable
    def subscribable_by?(user)
      false
    end
  end

  class Subscribable
    include Notifyd::Subscriptions
  end

  fixtures do
    @org = create(:organization)
    @user_owner = create(:user)
    @gist_org = create(:gist, owner: @org)
    @gist_user = create(:gist, owner: @user_owner)
    @user_one = create(:user)
    @repo = create(:repository)
    @issue = create(:issue, repository: @repo)
  end

  setup do
    @subscriptions_client_mock = mock("Subs::SubscriptionsClient")
      .responds_like_instance_of(Subs::SubscriptionsClient)
    @routing_settings_client_mock = mock("RS::RoutingSettingsClient")
      .responds_like_instance_of(RS::RoutingSettingsClient)
    @notifyd_client_mock = mock("Notifyd::Client")

    @notifyd_client_mock.stubs(:subscriptions).returns(@subscriptions_client_mock)
    @notifyd_client_mock.stubs(:routing_settings).returns(@routing_settings_client_mock)
    Notifyd.stubs(:client).returns(@notifyd_client_mock)


    @subscriptions_service_mock = mock("Notifyd::SubscriptionsService")
      .responds_like_instance_of(Notifyd::SubscriptionsService)
    @rs_service_mock = mock("Notifyd::RoutingSettingsService")
      .responds_like_instance_of(Notifyd::RoutingSettingsService)
    Notifyd::SubscriptionsService.stubs(:new).returns(@subscriptions_service_mock)
    Notifyd::RoutingSettingsService.stubs(:new).returns(@rs_service_mock)
  end

  context "#notifyd_subscribe_to_thread" do
    test "subscribes a user to a Gist thread owned by an organization with reason 'manual'" do
      @subscriptions_service_mock
      .expects(:save)
      .with([{
          reason: "manual",
          topics: [{ type: "gist", value: @gist_org.id.to_s }],
          filters: [
            {
              subject_type: "any",
              trigger: "any",
              match_rules: [
                { attribute: "thread_participant_activity", value: "true", match_rule: "eq" },
              ],
            }
          ],
          custom_fields: [
            { name: "category", value: "thread" },
            { name: "thread_type", value: "gist" },
            { name: "thread_id", value: @gist_org.id.to_s },
            { name: "owner_type", value: "organization" },
            { name: "owner_id", value: @org.id.to_s },
          ] }])
      .returns(true)

      @rs_service_mock
        .expects(:delete)
        .with([
          { name: "category", value: "thread" },
          { name: "thread_type", value: "gist" },
          { name: "thread_id", value: @gist_org.id.to_s },
          { name: "owner_type", value: "organization" },
          { name: "owner_id", value: @org.id.to_s },
        ])
        .returns(true)

      response = Subscribable.new.notifyd_subscribe_to_thread(@user_one, @org, @gist_org, "manual")
      assert response.value
      assert_equal response.class, Notifyd::Responses::Boolean
    end

    test "subscribes a user to a Gist thread owned by a user with reason 'manual'" do
      @subscriptions_service_mock
      .expects(:save)
      .with([{
          reason: "manual",
          topics: [{ type: "gist", value: @gist_user.id.to_s }],
          filters: [
            {
              subject_type: "any",
              trigger: "any",
              match_rules: [
                { attribute: "thread_participant_activity", value: "true", match_rule: "eq" },
              ]
            }
          ],
          custom_fields: [
            { name: "category", value: "thread" },
            { name: "thread_type", value: "gist" },
            { name: "thread_id", value: @gist_user.id.to_s },
            { name: "owner_type", value: "user" },
            { name: "owner_id", value: @user_owner.id.to_s },
          ] }])
      .returns(true)

      @rs_service_mock
        .expects(:delete)
        .with([
          { name: "category", value: "thread" },
          { name: "thread_type", value: "gist" },
          { name: "thread_id", value: @gist_user.id.to_s },
          { name: "owner_type", value: "user" },
          { name: "owner_id", value: @user_owner.id.to_s },
        ])
        .returns(true)

      response = Subscribable.new.notifyd_subscribe_to_thread(@user_one, @user_owner, @gist_user, "manual")
      assert response.value
      assert_equal response.class, Notifyd::Responses::Boolean
    end

    test "subscribe returns false when save fails" do
      @subscriptions_service_mock
      .expects(:save)
      .with([{
          reason: "manual",
          topics: [{ type: "gist", value: @gist_user.id.to_s }],
          filters: [
            {
              subject_type: "any",
              trigger: "any",
              match_rules: [
                { attribute: "thread_participant_activity", value: "true", match_rule: "eq" },
              ]
            }
          ],
          custom_fields: [
            { name: "category", value: "thread" },
            { name: "thread_type", value: "gist" },
            { name: "thread_id", value: @gist_user.id.to_s },
            { name: "owner_type", value: "user" },
            { name: "owner_id", value: @user_owner.id.to_s },
          ] }])
      .returns(false)


      response = Subscribable.new.notifyd_subscribe_to_thread(@user_one, @user_owner, @gist_user, "manual")
      refute response.value
      assert_equal response.class, Notifyd::Responses::Boolean
    end

    test "subscribe returns false when delete routing settings fails" do
      @subscriptions_service_mock
      .expects(:save)
      .with([{
          reason: "manual",
          topics: [{ type: "gist", value: @gist_user.id.to_s }],
          filters: [
            {
              subject_type: "any",
              trigger: "any",
              match_rules: [
                { attribute: "thread_participant_activity", value: "true", match_rule: "eq" },
              ]
            }
          ],
          custom_fields: [
            { name: "category", value: "thread" },
            { name: "thread_type", value: "gist" },
            { name: "thread_id", value: @gist_user.id.to_s },
            { name: "owner_type", value: "user" },
            { name: "owner_id", value: @user_owner.id.to_s },
          ] }])
      .returns(true)

      @rs_service_mock
      .expects(:delete)
      .with([
        { name: "category", value: "thread" },
        { name: "thread_type", value: "gist" },
        { name: "thread_id", value: @gist_user.id.to_s },
        { name: "owner_type", value: "user" },
        { name: "owner_id", value: @user_owner.id.to_s },
      ])
      .returns(false)

      response = Subscribable.new.notifyd_subscribe_to_thread(@user_one, @user_owner, @gist_user, "manual")
      refute response.value
      assert_equal response.class, Notifyd::Responses::Boolean
    end

    test "returns false when thread does not respond_to subscribable_by?" do
      response = Subscribable.new.notifyd_subscribe_to_thread(@user_one, @user_owner, true, "manual")
      refute response.value
      assert_equal response.class, Notifyd::Responses::Boolean
    end

    test "returns false when thread returns false for subscribable_by?" do
      response = Subscribable.new.notifyd_subscribe_to_thread(@user_one, @user_owner, NonSubscribable.new, "manual")
      refute response.value
      assert_equal response.class, Notifyd::Responses::Boolean
    end
  end

  context "#unsubscribe_from_thread" do
    test "unsubscribes a user from a Gist thread" do
      @subscriptions_service_mock
      .expects(:delete)
      .with([
            { name: "category", value: "thread" },
            { name: "thread_type", value: "gist" },
            { name: "thread_id", value: @gist_org.id.to_s },
            { name: "owner_type", value: "organization" },
            { name: "owner_id", value: @org.id.to_s }])
      .returns(true)

      @rs_service_mock
        .expects(:save)
        .with([RS::RoutingSetting.new(
            user_id: @user_one.id,
            name: "ignore",
            topics: [RS::Topic.new(type: "gist", value: @gist_org.id.to_s)],
            filters: [
              RS::Filter.new(reason: "comment", subject_type: "any", trigger: "any"),
              RS::Filter.new(reason: "author", subject_type: "any", trigger: "any"),
              RS::Filter.new(reason: "manual", subject_type: "any", trigger: "any"),
            ],
            channels: [RS::Channel.new(name: "ALL", enabled: false)],
            custom_fields: [
              RS::CustomField.new(name: "category", value: "thread"),
              RS::CustomField.new(name: "thread_type", value: "gist"),
              RS::CustomField.new(name: "thread_id", value: @gist_org.id.to_s),
              RS::CustomField.new(name: "owner_type", value: "organization"),
              RS::CustomField.new(name: "owner_id", value: @org.id.to_s)]
            )])
        .returns(true)

      Notifyd::SubscriptionsService.expects(:new).with(@user_one, GitHub.flipper[:notifyd_primary_gist].enabled?).returns(@subscriptions_service_mock)
      Notifyd::RoutingSettingsService.expects(:new).with(@user_one, GitHub.flipper[:notifyd_primary_gist].enabled?).returns(@rs_service_mock)

      response = Subscribable.new.notifyd_unsubscribe_from_thread(@user_one, @gist_org)
      assert response.value
      assert_equal response.class, Notifyd::Responses::Boolean
    end

    test "unsubscribes returns false when delete fails" do
      @subscriptions_service_mock
      .expects(:delete)
      .with([
        { name: "category", value: "thread" },
        { name: "thread_type", value: "gist" },
        { name: "thread_id", value: @gist_org.id.to_s },
        { name: "owner_type", value: "organization" },
        { name: "owner_id", value: @org.id.to_s }
      ]).returns(false)

      response = Subscribable.new.notifyd_unsubscribe_from_thread(@user_one, @gist_org)
      refute response.value
      assert_equal response.class, Notifyd::Responses::Boolean
    end

    test "unsubscribes a user from an Issue thread" do
      @subscriptions_service_mock
      .expects(:delete)
      .with([
            { name: "category", value: "thread" },
            { name: "thread_type", value: "issue" },
            { name: "thread_id", value: @issue.id.to_s },
            { name: "owner_type", value: "repository" },
            { name: "owner_id", value: @repo.id.to_s },
            { name: "repository_id", value: @repo.id.to_s }])
      .returns(true)

      @rs_service_mock
        .expects(:save)
        .with([RS::RoutingSetting.new(
            user_id: @user_one.id,
            name: "ignore",
            topics: [RS::Topic.new(type: "issue", value: @issue.id.to_s)],
            filters: [
              RS::Filter.new(
                subject_type: "any",
                trigger: "any",
                reason: "any",
                match_rules: [
                  RS::MatchRule.new(attribute: "thread_participant_activity", value: "true", match_rule: "eq"),
                  RS::MatchRule.new(value: "notify_muted", match_rule: "not_in_reason_group"),
                ]
              ),
            ],
            channels: [RS::Channel.new(name: "ALL", enabled: false)],
            custom_fields: [
              RS::CustomField.new(name: "category", value: "thread"),
              RS::CustomField.new(name: "thread_type", value: "issue"),
              RS::CustomField.new(name: "thread_id", value: @issue.id.to_s),
              RS::CustomField.new(name: "owner_type", value: "repository"),
              RS::CustomField.new(name: "owner_id", value: @repo.id.to_s),
              RS::CustomField.new(name: "repository_id", value: @repo.id.to_s)]
            )])
        .returns(true)

      Notifyd::SubscriptionsService.expects(:new).with(@user_one, GitHub.flipper[:notifyd_issue_watch_activity_notify].enabled?).returns(@subscriptions_service_mock)
      Notifyd::RoutingSettingsService.expects(:new).with(@user_one, GitHub.flipper[:notifyd_issue_watch_activity_notify].enabled?).returns(@rs_service_mock)

      response = Subscribable.new.notifyd_unsubscribe_from_thread(@user_one, @issue)
      assert response.value
      assert_equal response.class, Notifyd::Responses::Boolean
    end
  end

  context "#notifyd_subscription_status" do
    test "returns invalid status if there's no subscription" do
      @subscriptions_service_mock
        .expects(:get_thread_subscription)
        .with("gist", @gist_user.id)
        .returns(nil)

      @rs_service_mock
        .expects(:get_thread_settings)
        .with("gist", @gist_user.id)
        .returns(nil)

      subscriber = create(:user)

      refute Subscribable.new.notifyd_subscription_status(subscriber, @user_owner, @gist_user).valid_subscription_exists?
    end

    test "returns valid status if there's a valid subscription" do
      subscriber = create(:user)

      @subscriptions_service_mock
        .expects(:get_thread_subscription)
        .with("gist", @gist_user.id)
        .returns(Subs::Subscription.new({
          id: 111,
          user_id: subscriber.id,
          custom_fields: [
            Subs::CustomField.new(name: "thread_type", value: "gist"),
            Subs::CustomField.new(name: "thread_id", value: @gist_user.id.to_s),
          ]
        }))

      @rs_service_mock
        .expects(:get_thread_settings)
        .with("gist", @gist_user.id)
        .returns(nil)


      subscription_status = Subscribable.new.notifyd_subscription_status(subscriber, @user_owner, @gist_user)
      assert subscription_status.valid_subscription_exists?
      assert subscription_status.subscribed?
    end

    test "returns ignored status if there's a valid subscription ignored by settings" do
      subscriber = create(:user)

      @subscriptions_service_mock
        .expects(:get_thread_subscription)
        .with("gist", @gist_user.id)
        .returns(Subs::Subscription.new({
          id: 111,
          user_id: subscriber.id,
          custom_fields: [
            Subs::CustomField.new(name: "thread_type", value: "gist"),
            Subs::CustomField.new(name: "thread_id", value: @gist_user.id.to_s),
          ]
        }))

      @rs_service_mock
        .expects(:get_thread_settings)
        .with("gist", @gist_user.id)
        .returns(RS::RoutingSetting.new(
          user_id: subscriber.id,
          name: "ignore",
          topics: [RS::Topic.new(type: "gist", value: @gist_user.id.to_s)],
          filters: [
            RS::Filter.new(reason: "comment", subject_type: "any", trigger: "any"),
            RS::Filter.new(reason: "author", subject_type: "any", trigger: "any"),
            RS::Filter.new(reason: "manual", subject_type: "any", trigger: "any"),
          ],
          channels: [RS::Channel.new(name: "ALL", enabled: false)],
          custom_fields: [
            RS::CustomField.new(name: "thread_type", value: "gist"),
            RS::CustomField.new(name: "thread_id", value: @gist_user.id.to_s),
          ]))

      subscription_status = Subscribable.new.notifyd_subscription_status(subscriber, @user_owner, @gist_user)
      assert subscription_status.valid_subscription_exists?
      assert subscription_status.ignored?
      refute subscription_status.subscribed?
    end

    test "returns label subscription if there's no thread subscription", skip_if_feature_disabled: :notifyd_label_subscriptions do
      subscriber = create(:user)
      label = create(:label, repository: @repo, name: "bug")
      @issue.add_labels([label])

      @subscriptions_service_mock
      .expects(:get_thread_subscription)
      .with("issue", @issue.id)
      .returns(nil)

      @subscriptions_service_mock
      .expects(:get_thread_label_subscriptions)
      .with(@repo, @issue)
      .returns([Notifyd::LabelSubscription.new(subscriber, label_subscriptions(subscriber, @repo, @issue, label))])

      @rs_service_mock
      .expects(:get_thread_settings)
      .with("issue", @issue.id)
      .returns(nil)

      subscription_status = Subscribable.new.notifyd_subscription_status(subscriber, @repo, @issue)

      assert subscription_status.success?
      assert subscription_status.value.is_a?(Notifyd::LabelSubscription)
      assert subscription_status.valid?
      refute subscription_status.ignored?
      assert subscription_status.subscribed?
    end

    test "returns thread subscription if both thread and label subscription exists", skip_if_feature_disabled: :notifyd_label_subscriptions do
      subscriber = create(:user)
      label = create(:label, repository: @repo, name: "bug")
      @issue.add_labels([label])

      @subscriptions_service_mock
        .expects(:get_thread_subscription)
        .with("issue", @issue.id)
        .returns(Subs::Subscription.new({
          id: 111,
          user_id: subscriber.id,
          custom_fields: [
            Subs::CustomField.new(name: "thread_type", value: "issue"),
            Subs::CustomField.new(name: "thread_id", value: @issue.id.to_s),
          ]
        }))

      @subscriptions_service_mock
      .expects(:get_thread_label_subscriptions)
      .never

      @rs_service_mock
      .expects(:get_thread_settings)
      .with("issue", @issue.id)
      .returns(nil)

      subscription_status = Subscribable.new.notifyd_subscription_status(subscriber, @repo, @issue)
      assert subscription_status.success?
      assert subscription_status.value.is_a?(Notifyd::ThreadSubscription)
      assert subscription_status.valid?
      refute subscription_status.ignored?
      assert subscription_status.subscribed?
    end

    test "returns invalid status if thread subscription does not exist and label subscriptions are invalid", skip_if_feature_disabled: :notifyd_label_subscriptions do
      subscriber = create(:user)
      label = create(:label, repository: @repo, name: "bug")
      @issue.add_labels([label])

      @subscriptions_service_mock
        .expects(:get_thread_subscription)
        .with("issue", @issue.id)
        .returns(nil)

      @subscriptions_service_mock
      .expects(:get_thread_label_subscriptions)
      .returns([Notifyd::LabelSubscription.new(subscriber, invalid_label_subscriptions(subscriber))])

      @rs_service_mock
      .expects(:get_thread_settings)
      .with("issue", @issue.id)
      .returns(nil)

      refute Subscribable.new.notifyd_subscription_status(subscriber, @repo, @issue).valid_subscription_exists?
    end

    test "captures connection errors" do
      enable_feature_flag(:notifyd_primary_gist)
      enable_feature_flag(:notifyd_enable_gist_thread_subscriptions)

      subscriber = create(:user)

      @subscriptions_service_mock
        .expects(:get_thread_subscription)
        .with("gist", @gist_user.id)
        .raises(Notifyd::NetworkHelper::ConnectionError, "Connection failed")

      result = Subscribable.new.notifyd_subscription_status(subscriber, @user_owner, @gist_user)
      refute result.success?
    end
  end

  context "#notifyd_delete_thread_subscription", skip_enterprise: true do
    test "does nothing when FF is disabled" do
      disable_feature_flag(:notifyd_enable_issue_thread_subscriptions)
      @subscriptions_service_mock.expects(:delete).never
      @rs_service_mock.expects(:delete).never

      response = Subscribable.new.notifyd_delete_thread_subscription(@user_one, @issue)
      assert response.value
    end

    test "unsubscribes a user from an Issue thread" do
      enable_feature_flag(:notifyd_enable_issue_thread_subscriptions)

      @subscriptions_service_mock
      .expects(:delete)
      .with([
            { name: "category", value: "thread" },
            { name: "thread_type", value: "issue" },
            { name: "thread_id", value: @issue.id.to_s },
            { name: "owner_type", value: "repository" },
            { name: "owner_id", value: @repo.id.to_s },
            { name: "repository_id", value: @repo.id.to_s }])
      .returns(true)

      @rs_service_mock
      .expects(:delete)
      .with([
            { name: "category", value: "thread" },
            { name: "thread_type", value: "issue" },
            { name: "thread_id", value: @issue.id.to_s },
            { name: "owner_type", value: "repository" },
            { name: "owner_id", value: @repo.id.to_s },
            { name: "repository_id", value: @repo.id.to_s }])
      .returns(true)

      Notifyd::SubscriptionsService.expects(:new).with(@user_one, true).returns(@subscriptions_service_mock)
      Notifyd::RoutingSettingsService.expects(:new).with(@user_one, true).returns(@rs_service_mock)

      response = Subscribable.new.notifyd_delete_thread_subscription(@user_one, @issue)
      assert response.value
      assert_equal response.class, Notifyd::Responses::Boolean
    end

    test "unsubscribes returns false when delete fails" do
      enable_feature_flag(:notifyd_enable_issue_thread_subscriptions)

      @subscriptions_service_mock
      .expects(:delete)
      .with([
            { name: "category", value: "thread" },
            { name: "thread_type", value: "issue" },
            { name: "thread_id", value: @issue.id.to_s },
            { name: "owner_type", value: "repository" },
            { name: "owner_id", value: @repo.id.to_s },
            { name: "repository_id", value: @repo.id.to_s }])
      .returns(false)

      @rs_service_mock.expects(:delete).never

      response = Subscribable.new.notifyd_delete_thread_subscription(@user_one, @issue)
      refute response.value
      assert_equal response.class, Notifyd::Responses::Boolean
    end

    test "unsubscribes throws error when delete fails" do
      enable_feature_flag(:notifyd_enable_issue_thread_subscriptions)

      @subscriptions_service_mock
      .expects(:delete)
      .with([
            { name: "category", value: "thread" },
            { name: "thread_type", value: "issue" },
            { name: "thread_id", value: @issue.id.to_s },
            { name: "owner_type", value: "repository" },
            { name: "owner_id", value: @repo.id.to_s },
            { name: "repository_id", value: @repo.id.to_s }])
      .returns(true)

      @rs_service_mock
      .expects(:delete)
      .with([
            { name: "category", value: "thread" },
            { name: "thread_type", value: "issue" },
            { name: "thread_id", value: @issue.id.to_s },
            { name: "owner_type", value: "repository" },
            { name: "owner_id", value: @repo.id.to_s },
            { name: "repository_id", value: @repo.id.to_s }])
      .throws(StandardError.new)

      assert_raises StandardError do
        Subscribable.new.notifyd_delete_thread_subscription(@user_one, @issue)
      end
    end
  end
end
