# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/aqueduct_test_client"
require "aqueduct/test_helpers/test_server"

module Notifyd
  class NotifyPublisherTest < GitHub::TestCase
    include NotifydTestHelper
    include GitHub::LoggerHelper

    self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
    fixtures do
      @user = create(:user, :staff)
      @actor = create(:user)

      @repo_owner = create(:user)
      @repo = create(:repository, owner: @repo_owner)
      @repo_id = @repo.id
      @notification_id = "dummy-notification-1"
      @authzd_attributes = [
        Authzd::Proto::Attribute.wrap("subject.type", "Dummy"),
        Authzd::Proto::Attribute.wrap("subject.id", 4321)
      ]
      @mobile_layout = Notifyd::Proto::Layouts::Mobile::Basic.new({
        title: "@#{@actor.login} mentioned you",
        subtitle: "A meaningful subtitle",
        body: "Body",
        url: "https://github.com/foo/bar"
      })

      @related_topics = [
        { type: "label", value: "123" },
        { type: "label", value: "345" },
      ]

      @email_layout = Notifyd::Proto::Layouts::Email::Basic.new({
        subject: "@#{@actor.login} mentioned you",
        body: "Test body"
      })

      @subject = create(:issue)
      @triggered_at_time = Time.now

      @feature_switches = Google::Protobuf::Map.new(:string, :bool)
      @reason_groups = [
        { name: "notify_muted", reasons: %w[mention team_mention] },
        { name: "participant", reasons: %w[author comment assign state_change mention team_mention] },
      ]
    end

    setup do
      Notifyd::Scientist.stubs(:notifyd_enabled_for?).returns(false)

      GitHub.flipper[:publish_events_to_notifyd].enable
    end

    context "publishing message synchronously on enterprise", enterprise_only: true do
      test "does not send notifications if all features are disabled" do
        GitHub.flipper[:publish_events_to_notifyd].disable
        publish_message([{ reason: "mention", users: [@user] }])

        refute_aqueduct_jobs(queue: "notifyd_notify", app: "notifyd-production")
      end

      test "does not publish a notify staging message on review-lab for enterprise" do
        GitHub.stubs(:dynamic_lab?).returns(true)
        Notifyd::Scientist.stubs(:notifyd_enabled_for?).with(recipient: @user, subject: @subject).returns(true)

        publish_message([{ reason: "mention", users: [@user] }])

        refute_aqueduct_jobs(queue: "notifyd_notify", app: "notifyd-production")
      end
    end

    context "with an actor that is nil" do
      test "does not publish notification and logs message information", skip_enterprise: true do
        @actor.destroy
        Notifyd::Scientist.stubs(:notifyd_enabled_for?).with(recipient: @user, subject: @subject).returns(true)

        expected_log = {
          "Body" => "skipping message draft creation",
          "gh.actor.id" => "",
          "gh.notifyd.subject.type" => @subject.class.name,
          "gh.notifyd.subject.id" => @subject.id.to_s,
          "gh.notifyd.reason" => "nil"
        }

        assert_logged(**expected_log) do
          publish_message([{ reason: "mention", users: [@user] }])
        end

        refute_aqueduct_jobs(queue: "notifyd_notify", app: "notifyd-production")
      end
    end

    context "with an actor that is spammy", skip_enterprise: true do
      test "does not publish notification and logs message information" do
        @actor = create(:spammy_user)
        Notifyd::Scientist.stubs(:notifyd_enabled_for?).with(recipient: @user, subject: @subject).returns(true)

        expected_log = {
          "Body" => "skipping message draft creation",
          "gh.actor.id" => @actor.id,
          "gh.notifyd.subject.type" => @subject.class.name,
          "gh.notifyd.subject.id" => @subject.id.to_s,
          "gh.notifyd.reason" => "spammy"
        }

        assert_logged **expected_log do
          publish_message([{ reason: "mention", users: [@user] }])
        end

        refute_aqueduct_jobs(queue: "notifyd_notify", app: "notifyd-production")
      end
    end

    context "with an actor that is suspended", skip_enterprise: true do
      test "does not publish notification and logs message information" do
        @actor = create(:suspended_user)
        Notifyd::Scientist.stubs(:notifyd_enabled_for?).with(recipient: @user, subject: @subject).returns(true)

        expected_log = {
          "Body" => "skipping message draft creation",
          "gh.actor.id" => @actor.id,
          "gh.notifyd.subject.type" => @subject.class.name,
          "gh.notifyd.subject.id" => @subject.id.to_s,
          "gh.notifyd.reason" => "suspended"
        }

        assert_logged **expected_log do
          publish_message([{ reason: "mention", users: [@user] }])
        end

        refute_aqueduct_jobs(queue: "notifyd_notify", app: "notifyd-production")
      end
    end

    context "publishing message asynchronously" do
      test "schedules background job to publish notification FF enabled" do
        with_rails_env "development" do
          Notifyd::PublishNotifyMessageJob.expects(:set).never
        end

        args = {
          actor_id: @user.id,
          subject_id: 1,
          subject_klass: @subject.class.name,
          context: {
            actor_login: @user.login,
            operation: "create"
          }
        }

        Timecop.freeze do
          assert_enqueued_with(job: Notifyd::PublishNotifyMessageJob, args: [args.merge(triggered_at: Time.now)]) do
            Notifyd::NotifyPublisher.new.async_publish(**args)
          end
        end
      end

      test "does not schedule background job to publish notification if publish_events_to_notifyd feature flag disabled" do
        GitHub.flipper[:publish_events_to_notifyd].disable
        assert_no_enqueued_jobs do
          Notifyd::NotifyPublisher.new.async_publish(actor_id: @user.id, subject_id: 1, subject_klass: @subject.class.name)
        end
      end

      test "schedules background job with wait for spam checks in production FF enabled", skip_enterprise: true do
        with_rails_env "production" do
          Notifyd::PublishNotifyMessageJob.expects(:set)
            .with(wait: GitHub::SpamChecker::DELAY_FOR_EXTERNAL_CHECKS)
            .returns(Notifyd::PublishNotifyMessageJob)
        end

        args = {
          actor_id: @user.id,
          subject_id: 1,
          subject_klass: @subject.class.name,
          context: {
            actor_login: @user.login,
            operation: "create"
          }
        }

        Timecop.freeze do
          assert_enqueued_with(job: Notifyd::PublishNotifyMessageJob, args: [args.merge(triggered_at: Time.now)]) do
            Notifyd::NotifyPublisher.new.async_publish(**args)
          end
        end
      end
    end

    private

    def publish_message(explicit_recipients)
      Notifyd::NotifyPublisher
        .new(aqueduct_factory: aqueduct_factory)
        .publish(
          actor_id: @actor.id,
          repository_id: @repo_id,
          owner_id: @repo_owner.id,
          owner_type: (@repo_owner.user? ? :user : :organization),
          authzd_attributes: @authzd_attributes,
          saml_enforcement: { skip_enforcement: true },
          explicit_recipients: explicit_recipients,
          mobile_layout: @mobile_layout,
          email_layout: @email_layout,
          related_topics: @related_topics,
          subject: @subject,
          triggered_at: @triggered_at_time,
          trigger: "create",
          attributes: [],
          feature_switches: @feature_switches,
          reason_groups: @reason_groups
        )
    end
  end
end
