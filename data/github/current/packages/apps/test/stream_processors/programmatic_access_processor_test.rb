# typed: true
# frozen_string_literal: true

require "test_helper"

module GitHub::StreamProcessors
  class ProgrammaticAccessProcessorTest < GitHub::TestCase
    include HydroTestHelpers
    include DogstatsTestHelpers

    fixtures do
      @access = create(:user_programmatic_access)
    end

    setup do
      @processor = GitHub::StreamProcessors::ProgrammaticAccessProcessor.new
    end

    def publish(message)
      hydro_topic =
        if GitHub.multi_tenant_enterprise?
          "authnd.credential.v0.ProgrammaticAccess.Event"
        elsif GitHub.enterprise?
          "authnd.credential.enterprise.v0.ProgrammaticAccess.Event"
        else
          "authnd.credential.test.v0.ProgrammaticAccess.Event"
        end

      hydro_publisher.publish(
        message,
        schema: "authnd.v0.ProgrammaticAccessEvent",
        topic: hydro_topic,
      )
    end

    def create_message(type: :EXPIRED, reason: "security", access: @access, catalog_service: "authnd_tester", tenant: nil)
      msg = {
        actor_id: access.user_id,
        credential_id: 26044,
        credential_suffix: "wSHxr2SA",
        access_id: access.id,
        credential_expires_at_utc: 1.hour.ago,
        credential_issued_at_utc: 31.days.ago,
        event_type: type,
        event_reason: reason,
        catalog_service: catalog_service,
        request_id: SecureRandom.uuid,
        send_notification: true,
      }

      if GitHub.multi_tenant_enterprise?
        tenant ||= Business.find(access.owner.business_id)
        msg[:tenant_id] = tenant.id
      end

      msg
    end

    def publish_and_consume(message)
      publish(message)
      yield
    end

    test "calls the mailer action with the pat" do
      Timecop.freeze do
        ProgrammaticAccess.stubs(:find_or_nil).with(@access.id).returns(@access)

        AccountMailer
          .expects(:programmatic_access_expired_notice)
          .with(@access)
          .returns(stub(deliver_later: true))

        publish_and_consume(create_message) do
          run_processor(@processor, allowed_primary_query_count: 1)
        end

        assert_dogstats_increment "programmatic_access_events.messages.processed", tags: ["event_type:expired"]
      end
    end

    test "does not call the mailer action if the pat is not found" do
      AccountMailer.expects(:programmatic_access_expired_notice).never
      publish_and_consume(create_message.merge(access_id: 0)) do
        run_processor(@processor, allowed_primary_query_count: 1)
      end

      assert_dogstats_increment "github.stream_processor.message_skipped", tags: ["reason:access_not_found"]
    end

    test "skips mailer for non mailer event types" do
      AccountMailer.expects(:programmatic_access_expired_notice).never

      publish(create_message(type: :UNKNOWN))
      publish(create_message(type: :ISSUED))
      publish(create_message(type: :REVOKED))
      run_processor(@processor, allowed_primary_query_count: 3)

      assert_dogstats_increment 3, "github.stream_processor.message_skipped", tags: ["reason:not_mailer_event"]
    end

    test "processes multiple messages" do
      Timecop.freeze do
        other_access = create(:user_programmatic_access)
        [
          create_message(type: :EXPIRATION_WARNING, reason: "7d", access: other_access),
          create_message(type: :EXPIRATION_WARNING, reason: "7d"),
          create_message(type: :EXPIRATION_WARNING, reason: "1d"), # should be skipped within threshold
          create_message(type: :EXPIRED, reason: ""),
        ].each { |message| publish(message) }

        run_processor(@processor, allowed_primary_query_count: 8)

        assert_dogstats_increment 2, "programmatic_access_events.messages.processed", tags: ["event_type:expiration_warning"]
        assert_dogstats_increment 1, "programmatic_access_events.messages.processed", tags: ["event_type:expired"]
      end
    end

    test "does not mail the same event twice within a day" do
      AccountMailer
        .expects(:programmatic_access_expiration_warning_notice)
        .with(@access, "1d")
        .returns(stub(deliver_later: true))
        .once

      Timecop.freeze(Time.now) do
        publish_and_consume(create_message(type: :EXPIRATION_WARNING, reason: "1d")) do
          run_processor(@processor, allowed_primary_query_count: 2)
        end
      end

      Timecop.freeze(Time.now + 5.minutes) do
        publish_and_consume(create_message(type: :EXPIRATION_WARNING, reason: "1d")) do # should be skipped
          run_processor(@processor, allowed_primary_query_count: 4)
        end
      end

      assert_dogstats_increment 1, "programmatic_access_events.messages.processed", tags: ["event_type:expiration_warning"]
    end

    test "can mail the same event twice after a day" do
      AccountMailer
        .expects(:programmatic_access_expired_notice)
        .with(@access)
        .returns(stub(deliver_later: true))
        .twice

      Timecop.freeze(Time.now) do
        publish_and_consume(create_message(type: :EXPIRED)) do
          run_processor(@processor, allowed_primary_query_count: 2)
        end
      end

      Timecop.freeze(Time.now + 7.days) do
        publish_and_consume(create_message(type: :EXPIRED)) do
          run_processor(@processor, allowed_primary_query_count: 4)
        end
      end
    end

    test "instruments credential revoke event" do
      events = subscribe("personal_access_token.credential_revoked")

      expected_payload = {
        user_programmatic_access_id: @access.id,
        user_programmatic_access_name: @access.name,
        user: @access.owner.login,
        user_id: @access.owner.id,
      }

      message = create_message(type: :REVOKED, access: @access, catalog_service: "github/secret_scanning")
      publish_and_consume(message) do
        run_processor(@processor, allowed_primary_query_count: 4)
      end

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload, event.payload
      assert_dogstats_increment 1, "programmatic_access_events.messages.processed", tags: ["event_type:revoked"]
    end

    test "does not instrument credential revoke event if catalog service was not secret_scanning" do
      events = subscribe("personal_access_token.credential_revoked")

      message = create_message(type: :REVOKED, access: @access)
      publish_and_consume(message) do
        run_processor(@processor, allowed_primary_query_count: 1)
      end

      refute event = events.pop, "an event was not expected"
    end

    test "instruments credential expiration event" do
      Timecop.freeze do
        events = subscribe("personal_access_token.credential_expired")

        expected_payload = {
          user_programmatic_access_id: @access.id,
          user_programmatic_access_name: @access.name,
          user_programmatic_access_expired_at: 1.hour.ago.iso8601,
          user: @access.owner.login,
          user_id: @access.owner.id,
        }

        publish_and_consume(create_message(type: :EXPIRED, reason: "", access: @access, catalog_service: "authnd-notifier")) do
          run_processor(@processor, allowed_primary_query_count: 5)
        end

        assert event = events.pop, "an event was expected"
        assert_same_hash expected_payload, event.payload
        assert_dogstats_increment 1, "programmatic_access_events.messages.processed", tags: ["event_type:expired"]
      end
    end

    test "does not instrument credential expiration event if catalog service isn't viable" do
      events = subscribe("personal_access_token.credential_expired")

      message = create_message(type: :EXPIRED, reason: "", access: @access)
      publish_and_consume(message) do
        run_processor(@processor, allowed_primary_query_count: 2)
      end

      refute event = events.pop, "an event was not expected"
    end
  end
end
