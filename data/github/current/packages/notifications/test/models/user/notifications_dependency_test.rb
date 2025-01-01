# typed: true
# frozen_string_literal: true

require "test_helper"

class NotificationsDependencyTest < GitHub::TestCase
  include NewsiesHelper
  include ConditionalAccess::FilterTestHelper
  Subs = Notifyd::Proto::Subscriptions

  fixtures do
    @free_user = create(:user, login: "free-user", email: "free-user@example.com")

    @staffer = create(:staff_admin_user, login: "staffer", plan: "medium", email: "staffer@example.com")
    @paid_org = create(:organization, admin: @staffer, plan: GitHub::Plan.non_free_org_plans.first.name)

    @user = create(:user).tap { |u| enable_notifications_for_user(u, enabled_handlers: ["web"]) }
    @repo = create(:repository, owner: @user)
    @labels = create_list(:label, 2, repository: @repo)

    @private_repo = create(:private_repository).tap { |r| r.add_member(@user) }

    @saml_org = create(:business_plus_org)
    @saml_identity = create(:external_identity, user: @user, org: @saml_org)
    @saml_org_owned_repo = create(:private_repository, owner: @saml_org)

    [@repo, @private_repo, @saml_org_owned_repo].each { |r| @user.watch_repo(r) }

    GitHub.flipper[:notifyd_issue_watch_activity_notify].disable
    perform_enqueued_jobs(only: [SubscribeAndNotifyJob, Newsies::DeliverNotificationsJob]) do
      issues = create_list(:issue, 3, repository: @repo)
      issues[0..1].each { |issue| GitHub.newsies.web.mark_thread_read(@user, issue) }

      private_issues = create_list(:issue, 3, repository: @private_repo)
      GitHub.newsies.web.mark_thread_read(@user, private_issues.first)

      saml_issue = create(:issue, repository: @saml_org_owned_repo)
      GitHub.newsies.web.mark_thread_read(@user, saml_issue)
    end
  end

  setup do
    GitHub.stubs(:dynamic_lab?).returns(false)
    GitHub.stubs(:notifyd_production_url).returns("http://random-url.com")
  end

  def build_expected_label_subscriptions(repo, label_id)
    [{
      reason: "subscribed",
      topics: [{ type: "repository", value: repo.id.to_s }],
      filters: [
        {
          subject_type: "Issue",
          trigger: "create",
          match_rules: [
            { attribute: "has_label", value: label_id.to_s, match_rule: "eq" },
          ]
        },
        {
          subject_type: "IssueComment",
          trigger: "create",
          match_rules: [
            { attribute: "has_label", value: label_id.to_s, match_rule: "eq" },
          ]
        }
      ],
      custom_fields: [
        { name: "repository_id", value: repo.id.to_s },
        { name: "label_id", value: label_id.to_s },
        { name: "label_name", value: repo.labels.find(label_id).name },
        { name: "owner_id", value: repo.owner.id.to_s },
        { name: "subject_type", value: "Issue" },
      ]
    },
    {
      reason: "subscribed",
      topics: [{ type: "repository", value: repo.id.to_s }],
      filters: [
        {
          subject_type: "Issue",
          trigger: "labeled",
          match_rules: [
            { attribute: "added_label", value: label_id.to_s, match_rule: "eq" },
          ]
        },
        {
          subject_type: "Issue",
          trigger: "unlabeled",
          match_rules: [
            { attribute: "removed_label", value: label_id.to_s, match_rule: "eq" },
          ]
        }
      ],
      custom_fields: [
        { name: "repository_id", value: repo.id.to_s },
        { name: "label_id", value: label_id.to_s },
        { name: "label_name", value: repo.labels.find(label_id).name },
        { name: "owner_id", value: repo.owner.id.to_s },
        { name: "subject_type", value: "Issue" },
      ]
    }]
  end

  context "#disable_all_notifications" do
    test "updates routing settings" do
      GitHub.flipper[:notifyd_enable_issue_thread_subscriptions].enable
      Notifyd::RoutingSettingsService.any_instance.expects(:save).returns(true).with do |routing_settings|
        refute routing_settings[0].channels[0].enabled
        assert_equal routing_settings[0].channels[0].name, "EMAIL"
      end
      @user.disable_all_notifications
    end
  end

  context "#repo_notification_counts" do
    test "returns counts ordered from most to least unread notifications" do
      results = @user.repo_notification_counts(cap_filter: cap_authorizing_filter)

      assert_equal(
        [
          [@private_repo.nwo, 2, 3],
          [@repo.nwo, 1, 3],
          [@saml_org_owned_repo.nwo, 0, 1],
        ],
        results.map { |r| [r.repository.nwo, r.unread_count, r.total_count] }
      )
    end

    test "filters counts down to those that match the given status values" do
      results = @user.repo_notification_counts(
        cap_filter: cap_authorizing_filter,
        statuses: [:inbox_unread],
      )

      assert_equal(
        [
          [@private_repo.nwo, 2, 2],
          [@repo.nwo, 1, 1],
        ],
        results.map { |r| [r.repository.nwo, r.unread_count, r.total_count] }
      )
    end

    test "restricts the number of results to the given limit" do
      results = @user.repo_notification_counts(
        cap_filter: cap_authorizing_filter,
        limit: 1,
      )

      assert_equal(
        [
          [@private_repo.nwo, 2, 3],
        ],
        results.map { |r| [r.repository.nwo, r.unread_count, r.total_count] }
      )
    end

    test "filters out repositories that do not pass CAP authorization" do
      results = @user.repo_notification_counts(cap_filter: cap_unauthorizing_filter([@saml_org]))

      assert_equal(
        [
          [@private_repo.nwo, 2, 3],
          [@repo.nwo, 1, 3],
        ],
        results.map { |r| [r.repository.nwo, r.unread_count, r.total_count] }
      )
    end

    test "filters out repositories that the user cannot access" do
      @private_repo.remove_member(@user)

      results = @user.repo_notification_counts(cap_filter: cap_authorizing_filter)

      assert_equal(
        [
          [@repo.nwo, 1, 3],
          [@saml_org_owned_repo.nwo, 0, 1],
        ],
        results.map { |r| [r.repository.nwo, r.unread_count, r.total_count] }
      )
    end
  end

  context "#subscribe_to_labels" do
    test "returns true if the user successfully subscribes to a label via notifyd" do
      expected_subscriptions = []
      @labels.each do |label|
        expected_subscriptions.append(build_expected_label_subscriptions(@repo, label.id))
      end

      expected_subscriptions.flatten!

      notifyd_client_mock = mock("Notifyd::Client")
      Notifyd.stubs(:client).returns(notifyd_client_mock)

      subscriptions_client_mock = mock("Notifyd::Subscriptions::SubscriptionsClient")

      replace_by_custom_fields = [
        { name: "repository_id", value: @repo.id.to_s },
        { name: "label_id" }
      ]

      subscriptions_client_mock
        .expects(:batch_replace)
        .with(Subs::BatchReplaceRequest.new(user_id: @user.id, new_subscriptions: expected_subscriptions, replace_by_custom_fields: replace_by_custom_fields))
        .returns(Twirp::ClientResp.new(data: Subs::BatchReplaceResponse.new, error: nil))
      notifyd_client_mock.stubs(:subscriptions).returns(subscriptions_client_mock)

      resp = @user.subscribe_to_labels(@repo, @labels.map(&:id))
      assert resp
    end

    test "returns false if notifyd_production_url is not set" do
      GitHub.stubs(:notifyd_production_url).returns(nil)
      resp = @user.subscribe_to_labels(@repo, @labels.map(&:id))
      refute resp
    end

    test "returns false if the user does not have access to the repository" do
      new_repo = create(:private_repository)
      labels = create_list(:label, 2, repository: new_repo)
      resp = @user.subscribe_to_labels(new_repo, labels.map(&:id))
      refute resp
    end

    test "returns false if the repo owner has blocked the user" do
      new_repo = create(:public_repository)
      labels = create_list(:label, 2, repository: new_repo)

      new_repo.stubs(:pullable_by?).returns(true)
      new_repo.owner.block(@user)

      resp = @user.subscribe_to_labels(new_repo, labels.map(&:id))
      refute resp
    end

    test "returns true if the user successfully unsubscribes from all labels via notifyd" do
      notifyd_client_mock = mock("Notifyd::Client")
      Notifyd.stubs(:client).returns(notifyd_client_mock)

      get_response = Twirp::ClientResp.new(
        data: Subs::GetResponse.new(
          subscriptions: [Subs::Subscription.new(
            user_id: @user.id, custom_fields: [
              Subs::CustomField.new(name: "label_id", value: @labels[0].id.to_s),
              Subs::CustomField.new(name: "repository_id", value: @repo.id.to_s)]
          )],
        ),
        error: nil # no error
      )
      subscriptions_client_mock = mock("Notifyd::Subscriptions::SubscriptionsClient")
      subscriptions_client_mock.stubs(:get).returns(get_response)

      subscriptions_client_mock.stubs(:batch_replace).returns(Twirp::ClientResp.new(data: nil, error: nil))
      notifyd_client_mock.stubs(:subscriptions).returns(subscriptions_client_mock)

      resp = @user.subscribe_to_labels(@repo, [])
      assert resp
    end

    test "returns false if batch replace request to notifyd has a connection error" do
      notifyd_client_mock = mock("Notifyd::Client")
      Notifyd.stubs(:client).returns(notifyd_client_mock)

      subscriptions_client_mock = mock("Notifyd::Subscriptions::SubscriptionsClient")

      subscriptions_client_mock.stubs(:batch_replace).raises(Faraday::ConnectionFailed, "Connection failed")
      notifyd_client_mock.stubs(:subscriptions).returns(subscriptions_client_mock)

      resp = @user.subscribe_to_labels(@repo, [@labels[1].id])
      refute resp
    end

    test "returns false if batch replace response from notifyd contains errors" do
      notifyd_client_mock = mock("Notifyd::Client")
      Notifyd.stubs(:client).returns(notifyd_client_mock)

      subscriptions_client_mock = mock("Notifyd::SubscriptionsClient")
      subscriptions_client_mock.stubs(:batch_replace).returns(Twirp::ClientResp.new(data: nil, error: Twirp::Error.unavailable("unavailable")))
      notifyd_client_mock.stubs(:subscriptions).returns(subscriptions_client_mock)

      resp = @user.subscribe_to_labels(@repo, [@labels[1].id])
      refute resp
    end

    test "request error message" do
      err = Notifyd::NetworkHelper::ResponseError.new("Notifyd::Proto::BatchCreateAndDeleteRequest", Twirp::Error.unavailable("unavailable"))
      assert err.message, "Error response when calling the Notifyd::Proto::DeleteRequest RPC on notifyd. Code: unavailable. Message: unavailable"
    end
  end

  context "#update_organization_notifications_routing" do
    test "update routing settings for an org" do
      settings = GitHub.newsies.settings(@staffer)
      assert_equal @staffer.email, settings.email(@paid_org).address

      good_email = create :user_email, user: @staffer
      assert @staffer.update_organization_notifications_routing(@paid_org, good_email.email)

      settings = GitHub.newsies.settings(@staffer)
      assert_equal good_email.email, settings.email(@paid_org).address
    end

    test "raises an exception if email is not verified and clears it from newsies" do
      bad_email = "abc@def.com"

      GitHub.newsies.get_and_update_settings(@staffer) do |s|
        s.email :global, bad_email
      end

      settings = GitHub.newsies.settings(@staffer)
      assert_equal bad_email, settings.email(:global).address

      error = assert_raises(ArgumentError) do
        @staffer.update_organization_notifications_routing(@paid_org, bad_email)
      end
      assert_equal "Couldn't save #{bad_email} because it is not verified.", error.message

      settings = GitHub.newsies.settings(@staffer)
      refute_equal bad_email, settings.email(:global).address
    end

    test "raises an exception if newsies is unavailable and the email address doesn't belong to the user" do
      settings_response = Newsies::Responses::Boolean.new do
        raise T.must(Resiliency::Response::UnavailableExceptions.first)
      end
      GitHub.newsies.stubs(:get_and_update_settings).returns(settings_response)

      bad_email = "abc@def.com"
      error = assert_raises(User::NotificationServiceError) do
        @staffer.update_organization_notifications_routing(@paid_org, bad_email)
      end
      assert_equal "Unable to update notification settings.", error.message

      settings = GitHub.newsies.settings(@staffer)
      refute_equal bad_email, settings.email(:global).address
    end

    test "fails if newsies is unavailable and the email address is valid" do
      settings_response = Newsies::Responses::Boolean.new do
        raise T.must(Resiliency::Response::UnavailableExceptions.first)
      end
      GitHub.newsies.stubs(:get_and_update_settings).returns(settings_response)

      good_email = create :user_email, user: @staffer
      refute @staffer.update_organization_notifications_routing(@paid_org, good_email.email)

      settings = GitHub.newsies.settings(@staffer)
      refute_equal good_email.email, settings.email(@paid_org).address
    end

    test "raises an exception if trying to set setting for org user is not affiliated with" do
      random_org = create(:organization)

      good_email = create :user_email, user: @staffer
      error = assert_raises(ArgumentError) do
        @staffer.update_organization_notifications_routing(random_org, good_email.email)
      end
      assert_equal "You can only configure email routing for organizations you are affiliated with.", error.message
    end

    test "allows verified domain email if restrictions are enabled" do
      org = create(:business_plus_org, admin: @staffer)
      domain = create(:verifiable_domain, owner: org, verified: true)
      assert org.enable_notification_restrictions(actor: @staffer)
      email = "sombra@#{domain.domain}"
      @staffer.add_email(email).verify!

      assert @staffer.update_organization_notifications_routing(org, email)

      settings = GitHub.newsies.settings(@staffer)
      assert_equal email, settings.email(org).address
    end

    test "raises an exception if restrictions are enabled and email domain does not match verified domain" do
      org = create(:business_plus_org, admin: @staffer)
      domain = create(:verifiable_domain, owner: org, verified: true)
      assert org.enable_notification_restrictions(actor: @staffer)
      email = "sombra@some-other-domain.example.com"
      @staffer.add_email(email).verify!

      error = assert_raises(ArgumentError) do
        @staffer.update_organization_notifications_routing(org, email)
      end
      assert_equal "Couldn't save #{email} because it is not eligible to receive notifications for this organization.",
                   error.message
    end
  end

  context "subscribe_to_thread_types" do
    test "return false if user does not have pull access" do
      user = create(:user)
      repo = create(:private_repository)

      refute user.subscribe_to_thread_types(repo, [Release])
    end

    test "returns false if the user has been blocked from the repo" do
      user = create(:user)
      repo = create(:repository)

      repo.owner.block(user)

      refute user.subscribe_to_thread_types(repo, [Release])
    end

    test "subscribes to thread type subscription" do
      user = create(:user)
      repo = create(:repository)

      assert user.subscribe_to_thread_types(repo, [Release])
      assert_equal 1, Newsies::ThreadTypeSubscription.for_user(user.id).for_list(Newsies::List.to_object(repo)).count
    end
  end

  context "#set_preferred_notifications_query" do
    test "clears the stored value if given a blank query" do
      @free_user.set_preferred_notifications_query("is:unread")
      refute_nil Notifications::KV.store.get(@free_user.send(:preferred_notifications_query_key)).value!

      @free_user.set_preferred_notifications_query("")
      assert_nil Notifications::KV.store.get(@free_user.send(:preferred_notifications_query_key)).value!
    end

    test "stores a non-blank query" do
      @free_user.set_preferred_notifications_query("is:unread")
      assert_equal(
        Notifications::KV.store.get(@free_user.send(:preferred_notifications_query_key)).value!,
        "is:unread",
      )
    end
  end

  context "#set_prefers_notifications_group_by_list_view" do
    test "stores key if the key does not exist" do
      @free_user.set_prefers_notifications_group_by_list_view
      assert_predicate @free_user, :prefer_notifications_grouped_by_list?
    end
  end

  context "#unset_prefers_notifications_group_by_list_view" do
    test "deletes key if the key exists" do
      @free_user.set_prefers_notifications_group_by_list_view

      @free_user.unset_prefers_notifications_group_by_list_view
      refute_predicate @free_user, :prefer_notifications_grouped_by_list?
    end
  end

  context "#set_dismissed_unwatch_suggestions" do
    test "stores key if the key does not exist" do
      @free_user.set_dismissed_unwatch_suggestions
      assert_predicate @free_user, :dismissed_unwatch_suggestions?
    end

    test "by default stores the key to expire in 30 days" do
      Timecop.freeze do
        Notifications::KV.store.expects(:set).with(@free_user.send(:notifications_dismissed_unwatch_suggestions_key), "true", expires: 30.days.from_now)
        @free_user.set_dismissed_unwatch_suggestions
      end
    end

    test "by stores for 20 days when expiry_time is set to 20 days" do
      Timecop.freeze do
        Notifications::KV.store.expects(:set).with(@free_user.send(:notifications_dismissed_unwatch_suggestions_key), "true", expires: 20.days.from_now)
        @free_user.set_dismissed_unwatch_suggestions(expiry_time: 20.days.from_now)
      end
    end
  end

  context "#default_notification_email" do
    test "returns email attribute for non-EMU user with profile" do
      user = create :user
      create :profile, user: user

      assert_equal user.email, user.default_notification_email
      refute_equal user.profile_email, user.default_notification_email
    end

    test "returns email attribute for non-EMU user without profile" do
      user = create :user

      assert_nil user.profile
      assert_equal user.email, user.default_notification_email
    end

    test "returns email attribute for EMU user without profile", skip_enterprise: true do
      user = create :emu
      user.profile&.destroy
      assert_nil user.reload.profile

      assert_equal user.email, user.default_notification_email
    end

    test "returns profile email attribute for EMU user with profile", skip_enterprise: true do
      user = create :emu

      refute_equal user.email, user.default_notification_email
      assert_equal user.profile_email, user.default_notification_email
    end
  end

  unless GitHub.enterprise?
    context "subscribe_team" do
      test "returns false if user is not a member of the team" do
        member = create(:user)
        other_team = create(:team, organization: @paid_org)

        refute member.subscribe_team(other_team)
      end

      test "returns true when subscribe succeeds" do
        member = create(:user)
        team = create(:team, organization: @paid_org)
        team.add_member member

        # Unsubscribe member
        assert GitHub.newsies.unsubscribe(member, team).success?
        # Subscribe member
        assert member.subscribe_team(team)
      end
    end

    context "unsubscribe_team" do
      test "returns false if user is not a member of the team" do
        member = create(:user)
        other_team = create(:team, organization: @paid_org)

        refute member.subscribe_team(other_team)
      end

      test "returns true when unsubscribe succeeds" do
        member = create(:user)
        team = create(:team, organization: @paid_org)
        team.add_member member

        assert member.unsubscribe_team(team)
      end
    end

    context "ignore_team" do
      test "returns false if user is not a member of the team" do
        member = create(:user)
        other_team = create(:team, organization: @paid_org)

        refute member.subscribe_team(other_team)
      end

      test "returns true when ignore succeeds" do
        member = create(:user)
        team = create(:team, organization: @paid_org)
        team.add_member member

        assert member.ignore_team(team)
      end
    end

    context "watch_repo" do
      test "returns false when forbidden" do
        user = create(:user)
        repo = create(:repository)
        repo.stubs(:pullable_by?).returns(false)

        assert_equal false, user.watch_repo(repo)
      end

      test "returns true when subscribe_to_list succeeds" do
        user = create(:user)
        repo = create(:repository)
        GitHub.newsies.stubs(:subscribe_to_list).returns(NewsiesHelper::RESPONSE_SUCCESS)

        assert_equal true, user.watch_repo(repo)
      end
    end
  end
end
