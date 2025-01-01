# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class NotifydThreadSubscriptionTest < GitHub::TestCase
    Subs = Notifyd::Proto::Subscriptions
    RS = Notifyd::Proto::RoutingSettings

    setup do
      @repo = create(:repository)
      @user = create(:user)
      @repo.add_member(@user)
      @gist = create(:gist)
      @issue = create(:issue, repository: @repo)
    end

    context "#valid?" do
      test "returns true for the correctly formed thread subscription" do
        notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
          id: 123,
          user_id: @user.id,
          custom_fields: [
            Subs::CustomField.new(name: "thread_type", value: "gist"),
            Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
          ]
        )
        assert Notifyd::ThreadSubscription.new(@user, @gist, notifyd_subscription).valid_subscription_exists?
      end

      test "returns false if thread_type is not present" do
        notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
          id: 123,
          user_id: @user.id,
          custom_fields: [
            Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
          ]
        )
        refute Notifyd::ThreadSubscription.new(@user, @gist, notifyd_subscription).valid_subscription_exists?
      end

      test "returns false if thread_id is not present" do
        notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
          id: 123,
          user_id: @user.id,
          custom_fields: [
            Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
          ]
        )
        refute Notifyd::ThreadSubscription.new(@user, @gist, notifyd_subscription).valid_subscription_exists?
      end

      test "returns false for nil subscription when user is not an explicit recipient" do
        refute Notifyd::ThreadSubscription.new(@user, @gist, nil).valid_subscription_exists?
      end

      test "returns true for nil subscription when user is an author" do
        gist = create(:gist, user: @user)
        assert Notifyd::ThreadSubscription.new(@user, gist, nil).subscribed?
      end

      test "returns true for nil subscription when user is a commenter" do
        @gist.comments.create(body: "1", user: @user)
        assert Notifyd::ThreadSubscription.new(@user, @gist, nil).subscribed?
      end
    end

    context "#ignored?" do
      test "returns true if all reasons are present and channel is disabled" do
        notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
          id: 123,
          user_id: @user.id,
          custom_fields: [
            Subs::CustomField.new(name: "thread_type", value: "gist"),
            Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
          ]
        )

        notifyd_setting =
          Notifyd::Proto::RoutingSettings::RoutingSetting.new(
            id: 1,
            user_id: @user.id,
            name: "ignore",
            topics: [RS::Topic.new(type: "gist", value: @gist.id.to_s)],
            channels: [RS::Channel.new(name: "ALL", enabled: false)],
            custom_fields: [
              RS::CustomField.new(name: "thread_type", value: "gist"),
              RS::CustomField.new(name: "thread_id", value: @gist.id.to_s)],
            filters: [
              RS::Filter.new(subject_type: "any", trigger: "any", reason: "comment"),
              RS::Filter.new(subject_type: "any", trigger: "any", reason: "author"),
              RS::Filter.new(subject_type: "any", trigger: "any", reason: "manual")
            ])

        assert Notifyd::ThreadSubscription.new(@user, @gist, notifyd_subscription, notifyd_setting).ignored?
      end

      test "returns false if routing settings are not present" do
        notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
          id: 123,
          user_id: @user.id,
          custom_fields: [
            Subs::CustomField.new(name: "thread_type", value: "gist"),
            Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
          ]
        )
        refute Notifyd::ThreadSubscription.new(@user, @gist, notifyd_subscription).ignored?
      end

      test "returns false if reason author is not present" do
        notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
          id: 123,
          user_id: @user.id,
          custom_fields: [
            Subs::CustomField.new(name: "thread_type", value: "gist"),
            Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
          ]
        )

        notifyd_setting =
          Notifyd::Proto::RoutingSettings::RoutingSetting.new(
            id: 1,
            user_id: @user.id,
            name: "ignore",
            topics: [RS::Topic.new(type: "gist", value: @gist.id.to_s)],
            channels: [RS::Channel.new(name: "ALL", enabled: false)],
            custom_fields: [
              RS::CustomField.new(name: "thread_type", value: "gist"),
              RS::CustomField.new(name: "thread_id", value: @gist.id.to_s)],
            filters: [RS::Filter.new(subject_type: "any", trigger: "any", reason: "comment"),
                      RS::Filter.new(subject_type: "any", trigger: "any", reason: "manual")])

        refute Notifyd::ThreadSubscription.new(@user, @gist, notifyd_subscription, notifyd_setting).ignored?
      end

      test "returns false if reason comment is not present" do
        notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
          id: 123,
          user_id: @user.id,
          custom_fields: [
            Subs::CustomField.new(name: "thread_type", value: "gist"),
            Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
          ]
        )

        notifyd_setting =
          Notifyd::Proto::RoutingSettings::RoutingSetting.new(
            id: 1,
            user_id: @user.id,
            name: "ignore",
            topics: [RS::Topic.new(type: "gist", value: @gist.id.to_s)],
            channels: [RS::Channel.new(name: "ALL", enabled: false)],
            custom_fields: [
              RS::CustomField.new(name: "thread_type", value: "gist"),
              RS::CustomField.new(name: "thread_id", value: @gist.id.to_s)],
            filters: [RS::Filter.new(subject_type: "any", trigger: "any", reason: "author"),
                      RS::Filter.new(subject_type: "any", trigger: "any", reason: "manual")])

        refute Notifyd::ThreadSubscription.new(@user, @gist, notifyd_subscription, notifyd_setting).ignored?
      end

      test "returns false if reason manual is not present" do
        notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
          id: 123,
          user_id: @user.id,
          custom_fields: [
            Subs::CustomField.new(name: "thread_type", value: "gist"),
            Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
          ]
        )

        notifyd_setting =
          Notifyd::Proto::RoutingSettings::RoutingSetting.new(
            id: 1,
            user_id: @user.id,
            name: "ignore",
            topics: [RS::Topic.new(type: "gist", value: @gist.id.to_s)],
            channels: [RS::Channel.new(name: "ALL", enabled: false)],
            custom_fields: [
              RS::CustomField.new(name: "thread_type", value: "gist"),
              RS::CustomField.new(name: "thread_id", value: @gist.id.to_s)],
            filters: [RS::Filter.new(subject_type: "any", trigger: "any", reason: "author"),
                      RS::Filter.new(subject_type: "any", trigger: "any", reason: "comment")])

        refute Notifyd::ThreadSubscription.new(@user, @gist, notifyd_subscription, notifyd_setting).ignored?
      end

      test "returns false if all reasons are present but channel is enabled" do
        notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
          id: 123,
          user_id: @user.id,
          custom_fields: [
            Subs::CustomField.new(name: "thread_type", value: "gist"),
            Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
          ]
        )

        notifyd_setting =
          Notifyd::Proto::RoutingSettings::RoutingSetting.new(
            id: 1,
            user_id: @user.id,
            name: "ignore",
            topics: [RS::Topic.new(type: "gist", value: @gist.id.to_s)],
            channels: [RS::Channel.new(name: "ALL", enabled: true)],
            custom_fields: [
              RS::CustomField.new(name: "thread_type", value: "gist"),
              RS::CustomField.new(name: "thread_id", value: @gist.id.to_s)],
            filters: [
              RS::Filter.new(subject_type: "any", trigger: "any", reason: "comment"),
              RS::Filter.new(subject_type: "any", trigger: "any", reason: "author"),
              RS::Filter.new(subject_type: "any", trigger: "any", reason: "manual")])

        refute Notifyd::ThreadSubscription.new(@user, @gist, notifyd_subscription, notifyd_setting).ignored?
      end

      test "returns true if the routing setting has the new ignore match rules" do
        notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
          id: 123,
          user_id: @user.id,
          custom_fields: [
            Subs::CustomField.new(name: "thread_type", value: "gist"),
            Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
          ]
        )

        notifyd_setting =
          Notifyd::Proto::RoutingSettings::RoutingSetting.new(
            id: 1,
            user_id: @user.id,
            name: "ignore",
            topics: [RS::Topic.new(type: "gist", value: @gist.id.to_s)],
            channels: [RS::Channel.new(name: "ALL", enabled: false)],
            custom_fields: [
              RS::CustomField.new(name: "thread_type", value: "gist"),
              RS::CustomField.new(name: "thread_id", value: @gist.id.to_s)
            ],
            filters: [
              RS::Filter.new(
                subject_type: "any",
                reason: "any",
                trigger: "any",
                match_rules: [
                  RS::MatchRule.new({
                    attribute: "thread_participant_activity",
                    value: "true",
                    match_rule: "eq",
                  }),
                ]
              ),
            ]
          )

        assert_predicate Notifyd::ThreadSubscription.new(@user, @gist, notifyd_subscription, notifyd_setting), :ignored?
      end

      test "returns false if the new match rules don't apply" do
        notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
          id: 123,
          user_id: @user.id,
          custom_fields: [
            Subs::CustomField.new(name: "thread_type", value: "gist"),
            Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
          ]
        )

        notifyd_setting =
          Notifyd::Proto::RoutingSettings::RoutingSetting.new(
            id: 1,
            user_id: @user.id,
            name: "ignore",
            topics: [RS::Topic.new(type: "gist", value: @gist.id.to_s)],
            channels: [RS::Channel.new(name: "ALL", enabled: false)],
            custom_fields: [
              RS::CustomField.new(name: "thread_type", value: "gist"),
              RS::CustomField.new(name: "thread_id", value: @gist.id.to_s)
            ],
            filters: [
              RS::Filter.new(
                subject_type: "any",
                trigger: "any",
                reason: "any",
                match_rules: [
                  RS::MatchRule.new({
                    attribute: "thread_participant_activity",
                    value: "false",
                    match_rule: "eq",
                  }),
                ]
              ),
            ]
          )

        refute_predicate Notifyd::ThreadSubscription.new(@user, @gist, notifyd_subscription, notifyd_setting), :ignored?
      end
    end

    context "#subscribed?" do
      test "returns true when subscription is valid and not ignored" do
        notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
          id: 123,
          user_id: @user.id,
          custom_fields: [
            Subs::CustomField.new(name: "thread_type", value: "gist"),
            Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
          ]
        )

        assert Notifyd::ThreadSubscription.new(@user, @gist, notifyd_subscription).subscribed?
      end

      test "returns false if subscription is valid but ignored" do
        notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
          id: 123,
          user_id: @user.id,
          custom_fields: [
            Subs::CustomField.new(name: "thread_type", value: "gist"),
            Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
          ]
        )

        notifyd_setting =
          Notifyd::Proto::RoutingSettings::RoutingSetting.new(
            id: 1,
            user_id: @user.id,
            name: "ignore",
            topics: [RS::Topic.new(type: "gist", value: @gist.id.to_s)],
            channels: [RS::Channel.new(name: "ALL", enabled: false)],
            custom_fields: [
              RS::CustomField.new(name: "thread_type", value: "gist"),
              RS::CustomField.new(name: "thread_id", value: @gist.id.to_s)],
            filters: [
              RS::Filter.new(subject_type: "any", trigger: "any", reason: "comment"),
              RS::Filter.new(subject_type: "any", trigger: "any", reason: "author"),
              RS::Filter.new(subject_type: "any", trigger: "any", reason: "manual")])

        refute Notifyd::ThreadSubscription.new(@user, @gist, notifyd_subscription, notifyd_setting).subscribed?
      end

      test "returns false if subscription is invalid" do
        notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
          id: 123,
          user_id: @user.id,
          custom_fields: [
            Subs::CustomField.new(name: "thread_type", value: "gist"),
          ]
        )

        refute Notifyd::ThreadSubscription.new(@user, @gist, notifyd_subscription).subscribed?
      end

      test "returns false for nil subscription when user is not an explicit recipient" do
        refute Notifyd::ThreadSubscription.new(@user, @gist, nil).subscribed?
      end

      test "returns true for nil subscription when user is a gist author" do
        gist = create(:gist, user: @user)
        assert Notifyd::ThreadSubscription.new(@user, gist, nil).subscribed?
      end

      test "returns true for nil subscription when user is an issue author" do
        issue = create(:issue, user: @user)
        assert Notifyd::ThreadSubscription.new(@user, issue, nil).subscribed?
      end

      test "returns true for nil subscription when user is a gist commenter" do
        @gist.comments.create(body: "1", user: @user)
        assert Notifyd::ThreadSubscription.new(@user, @gist, nil).subscribed?
      end

      test "returns true for nil subscription when user is an issue commenter" do
        @issue.comments.create(body: "1", user: @user)
        assert Notifyd::ThreadSubscription.new(@user, @issue, nil).subscribed?
      end

      test "returns true for nil subscription when user is an issue assignee" do
        @issue.assignee = @user
        assert Notifyd::ThreadSubscription.new(@user, @issue, nil).subscribed?
      end

      test "returns true for nil subscription when user has closed an issue" do
        @issue.close(@user)
        assert Notifyd::ThreadSubscription.new(@user, @issue, nil).subscribed?
      end

      test "returns true for nil subscription when user has reopened an issue" do
        @issue.close
        @issue.open(@user)
        assert Notifyd::ThreadSubscription.new(@user, @issue, nil).subscribed?
      end

      test "returns false when user is an author but there's an ignore routing setting" do
        gist = create(:gist, user: @user)
        notifyd_setting =
          Notifyd::Proto::RoutingSettings::RoutingSetting.new(
            id: 1,
            user_id: @user.id,
            name: "ignore",
            topics: [RS::Topic.new(type: "gist", value: @gist.id.to_s)],
            channels: [RS::Channel.new(name: "ALL", enabled: false)],
            custom_fields: [
              RS::CustomField.new(name: "thread_type", value: "gist"),
              RS::CustomField.new(name: "thread_id", value: @gist.id.to_s)],
            filters: [
              RS::Filter.new(subject_type: "any", trigger: "any", reason: "comment"),
              RS::Filter.new(subject_type: "any", trigger: "any", reason: "author"),
              RS::Filter.new(subject_type: "any", trigger: "any", reason: "manual")])
        refute Notifyd::ThreadSubscription.new(@user, gist, nil, notifyd_setting).subscribed?
      end
    end

    context "#reason" do
      test "returns empty string if there is no notifyd subscription" do
        assert_equal "", Notifyd::ThreadSubscription.new(@user, @issue).reason
      end

      test "returns empty string if the notifyd subscription is not valid" do
        notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
          id: 123,
          user_id: @user.id,
          custom_fields: []
        )
        assert_equal "", Notifyd::ThreadSubscription.new(@user, @issue, notifyd_subscription).reason
      end

      test "returns the reason from the notifyd subscription" do
        notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
          id: 123,
          user_id: @user.id,
          reason: "subscribed",
          custom_fields: [
            Subs::CustomField.new(name: "thread_type", value: "issue"),
            Subs::CustomField.new(name: "thread_id", value: @issue.id.to_s),
          ]
        )
        assert_equal "subscribed", Notifyd::ThreadSubscription.new(@user, @issue, notifyd_subscription).reason
      end

      test "returns activity author reason when activity is older than the subscription" do
        # Create an issue for which we are an author for
        old_issue = create(:issue, user: @user, repository: @repo)

        Timecop.travel(1.minute.from_now) do
          notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
            id: 123,
            user_id: @user.id,
            reason: "subscribed",
            created_at: Time.now.to_i,
            custom_fields: [
              Subs::CustomField.new(name: "thread_type", value: "issue"),
              Subs::CustomField.new(name: "thread_id", value: old_issue.id.to_s),
            ]
          )
          assert_equal "author", Notifyd::ThreadSubscription.new(@user, old_issue, notifyd_subscription).reason
        end
      end

      test "returns subscription reason when user has not authored thread or comments" do
        # Create an issue for which we are NOT an author for
        old_issue = create(:issue, repository: @repo)

        Timecop.travel(1.minute.from_now) do
          notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
            id: 123,
            user_id: @user.id,
            reason: "subscribed",
            created_at: Time.now.to_i,
            custom_fields: [
              Subs::CustomField.new(name: "thread_type", value: "issue"),
              Subs::CustomField.new(name: "thread_id", value: old_issue.id.to_s),
            ]
          )
          assert_equal "subscribed", Notifyd::ThreadSubscription.new(@user, old_issue, notifyd_subscription).reason
        end
      end

      test "returns commenter activity reason when it is older than the subscription" do
        old_issue = create(:issue, repository: @repo)
        old_comment = create(:issue_comment, issue: old_issue, user: @user)

        Timecop.travel(1.minute.from_now) do
          notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
            id: 123,
            user_id: @user.id,
            reason: "subscribed",
            created_at: Time.now.to_i,
            custom_fields: [
              Subs::CustomField.new(name: "thread_type", value: "issue"),
              Subs::CustomField.new(name: "thread_id", value: old_issue.id.to_s),
            ]
          )
          assert_equal "comment", Notifyd::ThreadSubscription.new(@user, old_issue, notifyd_subscription).reason
        end
      end

      test "returns subscribed reason when user comments after subscribing" do
        old_issue = create(:issue, repository: @repo)
        notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
          id: 123,
          user_id: @user.id,
          reason: "subscribed",
          created_at: Time.now.to_i,
          custom_fields: [
            Subs::CustomField.new(name: "thread_type", value: "issue"),
            Subs::CustomField.new(name: "thread_id", value: old_issue.id.to_s),
          ]
        )

        Timecop.travel(1.minute.from_now) do
          create(:issue_comment, issue: old_issue, user: @user)
          assert_equal "subscribed", Notifyd::ThreadSubscription.new(@user, old_issue, notifyd_subscription).reason
        end
      end

      test "returns author activity reason when user has authored, commented and subscribed" do
        old_issue = create(:issue, user: @user, repository: @repo)

        Timecop.travel(1.minute.from_now) do
          old_comment = create(:issue_comment, issue: old_issue, user: @user)
          Timecop.travel(1.minute.from_now) do
            notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
              id: 123,
              user_id: @user.id,
              reason: "subscribed",
              created_at: Time.now.to_i,
              custom_fields: [
                Subs::CustomField.new(name: "thread_type", value: "issue"),
                Subs::CustomField.new(name: "thread_id", value: old_issue.id.to_s),
              ]
            )
            assert_equal "author", Notifyd::ThreadSubscription.new(@user, old_issue, notifyd_subscription).reason
          end
        end
      end

      test "returns assignee reason when user has been assigned to the thread" do
        issue = create(:assigned_issue, repository: @repo, assignee: @user)
        assert_equal "assign", Notifyd::ThreadSubscription.new(@user, issue, nil).reason
      end

      test "returns event activity reason if there is one" do
        issue = create(:issue, repository: @repo)
        create(:issue_event, actor: @user, issue: issue, event: "reopened")
        assert_equal "state_change", Notifyd::ThreadSubscription.new(@user, issue, nil).reason
      end

      test "returns activity reason when no subscription is present" do
        issue = create(:issue, repository: @repo)
        comment = create(:issue_comment, issue: issue, user: @user)
        assert_equal "comment", Notifyd::ThreadSubscription.new(@user, issue, nil).reason
      end
    end

    context "#created_at" do
      test "returns nil if there is no notifyd subscription" do
        assert_nil Notifyd::ThreadSubscription.new(@user, @issue).created_at
      end

      test "returns nil string if the notifyd subscription is not valid" do
        notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
          id: 123,
          user_id: @user.id,
          custom_fields: []
        )
        assert_nil Notifyd::ThreadSubscription.new(@user, @issue, notifyd_subscription).created_at
      end

      test "returns the created at date of the subscription" do
        Timecop.freeze do
          notifyd_subscription = Notifyd::Proto::Subscriptions::Subscription.new(
            id: 123,
            user_id: @user.id,
            reason: "subscribed",
            created_at: Time.now.to_i,
            custom_fields: [
              Subs::CustomField.new(name: "thread_type", value: "issue"),
              Subs::CustomField.new(name: "thread_id", value: @issue.id.to_s),
            ]
          )

          assert_equal Time.at(Time.now.to_i), Notifyd::ThreadSubscription.new(@user, @issue, notifyd_subscription).created_at
        end
      end

      test "returns the created at date of the ignored routing setting if ignored" do
        Timecop.freeze do
          notifyd_setting =
            Notifyd::Proto::RoutingSettings::RoutingSetting.new(
              id: 1,
              user_id: @user.id,
              name: "ignore",
              created_at: Time.now.to_i,
              topics: [RS::Topic.new(type: "gist", value: @gist.id.to_s)],
              channels: [RS::Channel.new(name: "ALL", enabled: false)],
              custom_fields: [
                RS::CustomField.new(name: "thread_type", value: "gist"),
                RS::CustomField.new(name: "thread_id", value: @gist.id.to_s)],
              filters: [
                RS::Filter.new(subject_type: "any", trigger: "any", reason: "comment"),
                RS::Filter.new(subject_type: "any", trigger: "any", reason: "author"),
                RS::Filter.new(subject_type: "any", trigger: "any", reason: "manual")
              ])

          assert Notifyd::ThreadSubscription.new(@user, @gist, nil, notifyd_setting).ignored?
          assert_equal Time.at(Time.now.to_i), Notifyd::ThreadSubscription.new(@user, @gist, nil, notifyd_setting).created_at
        end
      end

      test "returns nil for created at if ignored routing setting does not have a created at date" do
        Timecop.freeze do
          notifyd_setting =
            Notifyd::Proto::RoutingSettings::RoutingSetting.new(
              id: 1,
              user_id: @user.id,
              name: "ignore",
              topics: [RS::Topic.new(type: "gist", value: @gist.id.to_s)],
              channels: [RS::Channel.new(name: "ALL", enabled: false)],
              custom_fields: [
                RS::CustomField.new(name: "thread_type", value: "gist"),
                RS::CustomField.new(name: "thread_id", value: @gist.id.to_s)],
              filters: [
                RS::Filter.new(subject_type: "any", trigger: "any", reason: "comment"),
                RS::Filter.new(subject_type: "any", trigger: "any", reason: "author"),
                RS::Filter.new(subject_type: "any", trigger: "any", reason: "manual")
              ])

          assert Notifyd::ThreadSubscription.new(@user, @gist, nil, notifyd_setting).ignored?
          assert_nil Notifyd::ThreadSubscription.new(@user, @gist, nil, notifyd_setting).created_at
        end
      end
    end
  end
end
