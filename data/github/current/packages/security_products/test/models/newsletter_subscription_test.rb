# typed: true
# frozen_string_literal: true

require "test_helper"

class NewsletterSubscriptionTest < GitHub::TestCase
  include DependabotAlertsEnterpriseEnablementHelper

  fixtures do
    @subscriber = create(:user, login: "subscriber")

    @famous_repo = create(:repository, name: "famous_repo", created_at: 3.days.ago, owner: @subscriber)
    @famous_repo.update!(stargazer_count: 100)
    @famous_repo.update!(pushed_at: 1.minute.ago)

    @pending_weekly_vulnerability = NewsletterSubscription.subscribe(@subscriber, "vulnerability", "weekly")
    @pending_weekly_vulnerability.next_delivery_at = 1.hour.ago
    @pending_weekly_vulnerability.save

    @vulnerability = create :vulnerability_with_range
    @range = @vulnerability.vulnerable_version_ranges.first
    @famous_repo.repository_vulnerability_alerts.create(
    vulnerability_id: @vulnerability.id,
    vulnerable_version_range_id: @range.id,
    vulnerable_manifest_path: "http://www.github.com/github/github/gemfile.rb",
    state: "open")

    @famous_repo.enable_vulnerability_alerts(actor: @subscriber)
    assert_equal true, @subscriber.watch_repo(@famous_repo)

    # This is a count of the number of deliveries the current fixtures preset.
    @pending_deliveries = 1
  end

  setup do
    ActionMailer::Base.deliveries.clear

    stub_dependabot_alerts_enterprise_enablement if GitHub.enterprise?
  end

  test "user can subscribe to vulnerability newsletter" do
    letter = NewsletterSubscription.subscribe(@subscriber, "vulnerability", "weekly")
    assert letter
  end

  test "user can subscribe to newsletter only once" do
    NewsletterSubscription.subscribe(@subscriber, "vulnerability", "daily")
    NewsletterSubscription.subscribe(@subscriber, "vulnerability", "weekly")
    letters = NewsletterSubscription.where(user_id: @subscriber.id, name: "vulnerability")

    assert_equal 1, letters.size
    assert_equal "weekly", T.must(letters.first).kind
    assert T.must(letters.first).active
  end

  test "requires valid subscription name" do
    newsletter = create :newsletter_subscription, name: "vulnerability"

    assert newsletter.valid?

    newsletter.name = "whacky"
    refute newsletter.valid?
    assert newsletter.errors[:name].include?("is not included in the list")
  end

  test "requires valid subscription kind" do
    newsletter = create :newsletter_subscription

    newsletter.kind = "daily"
    assert newsletter.valid?

    newsletter.kind = "weekly"
    assert newsletter.valid?

    newsletter.kind = "monthly"
    assert newsletter.valid?

    newsletter.kind = "one_off"
    assert newsletter.valid?

    newsletter.kind = "forever"
    refute newsletter.valid?
    assert newsletter.errors[:kind].include?("is not included in the list")
  end

  test "requires user primary email" do
    @subscriber.emails.delete_all
    newsletter = NewsletterSubscription.new(user: @subscriber)
    refute newsletter.valid?
  end

  test "requires user be not suspended" do
    @subscriber.update!(suspended_at: Time.now)
    newsletter = NewsletterSubscription.new(user: @subscriber)
    refute newsletter.valid?
  end

  test ".subscribe records the subscribed_at timestamp" do
    newsletter = NewsletterSubscription.subscribe(@subscriber, "vulnerability", "weekly")
    refute_nil newsletter.subscribed_at
  end

  test "user can unsubscribe from newsletter" do
    letter = NewsletterSubscription.subscribe(@subscriber, "vulnerability", "daily")
    assert letter

    NewsletterSubscription.unsubscribe(letter.unsubscribe_token)
    assert_equal 0, NewsletterSubscription.active.where(user_id: @subscriber.id, name: "vulnerability").count
  end

  test "does not unsubscribe when token is not valid" do
    refute NewsletterSubscription.unsubscribe("octocat")
  end

  test "find unsubscribe token" do
    letter = NewsletterSubscription.subscribe(@subscriber, "vulnerability", "weekly")
    assert letter

    Timecop.freeze do
      token = letter.unsubscribe_token
      assert_equal token, NewsletterSubscription.get_unsubscribe_token(@subscriber, "vulnerability")
    end
  end

  test "validates a unsubscribe token" do
    letter = NewsletterSubscription.subscribe(@subscriber, "vulnerability", "weekly")
    assert letter

    Timecop.freeze do
      token = letter.unsubscribe_token
      assert_equal @subscriber, T.must(NewsletterSubscription.validate_token(token)).user
    end
  end

  test "delivers active newsletter subscriptions" do
    mock_mailer = stub(deliver_now: nil)
    VulnerabilityMailer.expects(:digest).returns(mock_mailer)
    mock_mailer.expects(:deliver_now).once
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    perform_enqueued_jobs(only: [NewsletterDeliveryRunJob]) do
      NewsletterSubscription.start_delivery(type: "vulnerability")
    end

    assert @pending_weekly_vulnerability.reload.next_delivery_at >= Time.now
    assert_equal @pending_deliveries, GitHub.dogstats.increments("newsletter.delivery.success").length
  end

  test "does not delivers active newsletter subscriptions when delivery fails" do
    NewsletterSubscription.any_instance.stubs(:deliver).raises(StandardError)
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    VulnerabilityMailer.any_instance.expects(:deliver_now).never

    perform_enqueued_jobs(only: [NewsletterDeliveryRunJob]) do
      NewsletterSubscription.start_delivery(type: "vulnerability")
    end

    GitHub.dogstats.increments("newsletter.delivery.error").each do |metric|
      assert metric.tags.include?("error:StandardError")
      assert metric.tags.include?("kind:weekly")
      assert metric.tags.include?("name:vulnerability")
    end
  end

  test "does not deliver active newsletter subscriptions to suspended users" do
    # @subscriber receives the vulnerability newsletter, let's mark them as suspended and verify they
    # don't receive the newsletter. Another user receives the explore newsletter and that should still be sent.
    @subscriber.update!(suspended_at: Time.now)

    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    VulnerabilityMailer.any_instance.expects(:deliver_now).never

    perform_enqueued_jobs(only: [NewsletterDeliveryRunJob]) do
      NewsletterSubscription.start_delivery(type: "vulnerability")
    end

    assert_equal @pending_weekly_vulnerability.next_delivery_at, @pending_weekly_vulnerability.reload.next_delivery_at
    assert_equal @pending_deliveries - 1, GitHub.dogstats.increments("newsletter.delivery.success").length
  end

  test "does not re-deliver subscriptions after they've been delivered" do
    @pending_weekly_vulnerability.sent_at = 10.minutes.ago
    @pending_weekly_vulnerability.save

    perform_enqueued_jobs(only: [NewsletterDeliveryRunJob]) do
      NewsletterSubscription.start_delivery(type: "vulnerability")
    end
    assert_equal @pending_deliveries - 1, ActionMailer::Base.deliveries.size
  end

  test "enqueues enough delivery run jobs to process all subscriptions" do
    # create more subs than is allowed by the limit
    create_list(:newsletter_subscription, 15, name: "vulnerability", kind: "weekly", next_delivery_at: 1.hour.ago)

    assert_equal 16, NewsletterSubscription.pending_delivery.count

    assert_enqueued_jobs 4, queue: :newsletter_delivery_run do
      NewsletterSubscription.stub_const(:DELIVERY_JOB_SUB_LIMIT, 5) do
        NewsletterSubscription.start_delivery(type: "vulnerability")
      end
    end
  end

  test "subscribe schedules vulnerability delivery" do
    sub = NewsletterSubscription.subscribe(@subscriber, "vulnerability", "weekly")
    refute sub.next_delivery_at.nil?
  end

  context "#resubscribe" do
    test "reactivates a subscription" do
      subscription = NewsletterSubscription.subscribe(@subscriber, "vulnerability", "weekly")
      NewsletterSubscription.unsubscribe(subscription.unsubscribe_token)
      refute subscription.reload.active?

      assert subscription.resubscribe
      assert subscription.reload.active?
    end

    test "returns true if the subscription is already active" do
      subscription = NewsletterSubscription.subscribe(@subscriber, "vulnerability", "weekly")
      assert subscription.active?
      assert subscription.resubscribe
    end

    test "updates subscribed_at timestamp" do
      time = Time.current
      subscription = NewsletterSubscription.subscribe(@subscriber, "vulnerability", "weekly")
      first_timestamp = subscription.subscribed_at
      NewsletterSubscription.unsubscribe(subscription.unsubscribe_token)

      Timecop.freeze(time + 1.minute) do
        subscription.reload.resubscribe
        refute_equal subscription.reload.subscribed_at, first_timestamp
      end
    end

    test "schedules the next delivery" do
      subscription = NewsletterSubscription.subscribe(@subscriber, "vulnerability", "weekly")
      NewsletterSubscription.unsubscribe(subscription.unsubscribe_token)
      subscription.update_column :next_delivery_at, nil
      refute subscription.reload.active?

      subscription.resubscribe
      refute_nil subscription.reload.next_delivery_at
    end
  end

  context ".subscribe" do
    test "resubscribe:false option does not activate an inactive subscription" do
      original_subscription = NewsletterSubscription.subscribe(@subscriber, "vulnerability", "weekly")
      assert original_subscription.active?

      original_subscription.unsubscribe
      refute original_subscription.reload.active?

      should_be_original_subscription = NewsletterSubscription.subscribe(@subscriber, "vulnerability", "weekly", resubscribe: false)
      refute original_subscription.reload.active?
      # ensure the subscription returned by subscribe method is the same as the original one
      assert_equal original_subscription, should_be_original_subscription
    end

    test "resubscribe:true option does reactivate an inactive subscription" do
      original_subscription = NewsletterSubscription.subscribe(@subscriber, "vulnerability", "weekly")
      assert original_subscription.active?

      original_subscription.unsubscribe
      refute original_subscription.reload.active?

      should_be_original_subscription = NewsletterSubscription.subscribe(@subscriber, "vulnerability", "weekly", resubscribe: true)
      assert original_subscription.reload.active?
      # ensure the subscription returned by subscribe method is the same as the original one
      assert_equal original_subscription, should_be_original_subscription
    end

    test "sets auto_subscribe to false by default" do
      subscription = NewsletterSubscription.subscribe(@subscriber, "vulnerability", "weekly")
      refute_predicate subscription, :auto_subscribed
    end
  end

  context "#unsubscribe" do
    test "deactivates a subscription" do
      subscription = NewsletterSubscription.subscribe(@subscriber, "vulnerability", "weekly")
      assert subscription.active?

      subscription.unsubscribe
      refute subscription.reload.active?
    end

    test "returns true if the subscription is already inactive" do
      subscription = NewsletterSubscription.subscribe(@subscriber, "vulnerability", "weekly")
      assert subscription.active?
      assert subscription.unsubscribe
    end
  end

  context ".unsubscribe_all" do
    test "deactivates currently active subscriptions" do
      subscription = NewsletterSubscription.subscribe(@subscriber, "vulnerability", "weekly")
      assert subscription.active?

      NewsletterSubscription.unsubscribe_all(@subscriber)

      refute subscription.reload.active?
    end

    test "returns true if there were no errors" do
      NewsletterSubscription.subscribe(@subscriber, "vulnerability", "weekly")
      assert NewsletterSubscription.unsubscribe_all(@subscriber)
    end

    test "returns true if no subscriptions exist for the user" do
      @subscriber.newsletter_subscriptions.delete_all
      assert_empty @subscriber.newsletter_subscriptions
      assert NewsletterSubscription.unsubscribe_all(@subscriber)
    end
  end

  context "#deliver" do
    test "doesn't raise errors if the user is nil" do
      @pending_weekly_vulnerability.user = nil
      refute @pending_weekly_vulnerability.deliver
    end

    # in production, we ended up a few hundred invalid newslettersubs:
    # we *think* users with active subscriptions were upgraded into organizations
    # which consequently caused them to receive an hourly flood of email,
    # which they couldn't unsubscribe from.
    test "doesn't send mail when subscription is in an invalid state" do
      news_sub = NewsletterSubscription.subscribe(create(:user), "vulnerability", "weekly")
      news_sub.next_delivery_at = 1.hour.ago

      news_sub.save!

      # let's pretend that this user got upgraded into an organization.
      # On production this would preserve the user_ids but for our purpose
      # swapping out the column id should suffice:

      org = create :organization
      repo = create :repository, owner: org
      rva = create :repository_vulnerability_alert, repository: repo
      news_sub.update_column(:user_id, org.id)

      # news_sub should now be set to an invalid state. let's try sending!
      news_sub.reload
      assert news_sub.active

      assert_equal 0, ActionMailer::Base.deliveries.size

      news_sub.deliver

      assert_equal 0, ActionMailer::Base.deliveries.size

      # now that we've tried to deliver mail in an invalid state,
      # let's check in on what happened to this news_sub,

      news_sub.reload

      # because it should have been deactivated:
      refute news_sub.active
    end

    test "sets tenant to the user's tenant" do
      on_multi_tenant_enterprise do
        user = create(:emu)
        business = user.enterprise_managed_business

        news_sub = NewsletterSubscription.subscribe(user, "vulnerability", "weekly")
        news_sub.next_delivery_at = 1.hour.ago

        news_sub.save!
        GitHub::CurrentTenant.expects(:set).with(business)

        news_sub.deliver
      end
    end
  end

  context "#pending_delivery?" do
    test "returns true when the subscription needs delivery" do
      news_sub = NewsletterSubscription.subscribe(create(:user), "vulnerability", "weekly")
      news_sub.next_delivery_at = 1.hour.ago
      news_sub.save

      assert news_sub.pending_delivery?
    end

    test "returns false when already sent" do
      news_sub = NewsletterSubscription.subscribe(create(:user), "vulnerability", "weekly")
      news_sub.next_delivery_at = 1.hour.from_now
      news_sub.save

      refute news_sub.pending_delivery?
    end

    test "returns false when inactive" do
      news_sub = NewsletterSubscription.subscribe(create(:user), "vulnerability", "weekly")
      news_sub.next_delivery_at = 1.hour.ago
      news_sub.active = false
      news_sub.save

      refute news_sub.pending_delivery?
    end
  end
end
