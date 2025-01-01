# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Reconciliation
    class SessionTest < GitHub::TestCase
      include DogstatsTestHelpers

      fixtures do
        @org = create(:business_plus_organization)
      end

      setup do
        FeatureFlagHelper.stubs(:cs_and_dbot_regularly_scheduled_full_reconciliation?).returns(true)
      end

      context "type validation" do
        test "raise error if type is not valid" do
          assert_raises(ArgumentError) do
            Session.new(owner_id: 1, type: "foo")
          end
        end
      end

      context "session id" do
        test "id includes both org id and start timestamp if there was a previous run" do
          session = Session.new(owner_id: @org.id, type: "repository_metadata")
          session.lock!

          id_components = session.id.split(".")

          assert_equal 2, id_components.size
          assert_equal @org.id.to_s, id_components.first
          assert_equal session.session_started_at.to_s, id_components.last
        end

        test "id only includes org id if there was no previous run" do
          session = Session.new(owner_id: @org.id, type: "repository_metadata")
          id_components = session.id.split(".")

          assert_equal 1, id_components.size
          assert_equal @org.id.to_s, id_components.first
        end
      end

      context "#session_started_at" do
        test "returns nil if this is the first run" do
          session = Session.new(owner_id: @org.id, type: "repository_metadata")
          refute session.session_started_at
        end

        test "returns a Time after it locks" do
          session = Session.new(owner_id: @org.id, type: "repository_metadata")
          session.lock!

          assert session.session_started_at.is_a?(Time)
        end
      end

      context "#ttl" do
        test "is set for repo metrics types" do
          metadata = Session.new(owner_id: @org.id, type: "repository_metadata")
          feature_status = Session.new(owner_id: @org.id, type: "feature_enablement")
          metadata.lock!
          feature_status.lock!

          assert metadata.ttl
          assert feature_status.ttl
        end

        test "is set for full scan for secret scanning" do
          ss = Session.new(owner_id: @org.id, type: "secret_scanning_alert")
          ss.lock!

          assert ss.ttl
        end

        test "is set for full scan for code scanning" do
          cs = Session.new(owner_id: @org.id, type: "code_scanning_alert")
          cs.lock!

          assert cs.ttl
        end

        test "is set for full scan for dependabot" do
          dbot = Session.new(owner_id: @org.id, type: "dependabot_alerts")
          dbot.lock!

          assert dbot.ttl
        end
      end

      context "locked?" do
        test "returns false if kv doesn't exist" do
          metadata = Session.new(owner_id: @org.id, type: "repository_metadata")
          dbot = Session.new(owner_id: @org.id, type: "dependabot_alerts")

          refute metadata.locked?
          refute dbot.locked?
        end

        test "returns true if kv exists and within the cooldown period" do
          dbot = Session.new(owner_id: @org.id, type: "dependabot_alerts")
          metadata = Session.new(owner_id: @org.id, type: "repository_metadata")
          dbot.lock!
          metadata.lock!

          Timecop.travel(1.day.from_now) do
            assert dbot.locked?
          end
        end

        test "returns false if kv exists but outside the cooldown period for alert metrics" do
          dbot = Session.new(owner_id: @org.id, type: "dependabot_alerts")
          metadata = Session.new(owner_id: @org.id, type: "repository_metadata")
          dbot.lock!
          metadata.lock!

          Timecop.travel(10.days.from_now) do
            refute dbot.locked?
          end
        end
      end

      context "#lock!" do
        test "returns a hash with the new session_started_at and last_session_started_at" do
          dbot = Session.new(owner_id: @org.id, type: "dependabot_alerts")
          session_started_at = dbot.session_started_at

          GitHub.logger.expects(:info).with(
            "Session locked.",
            has_entries({
              "gh.owner.id": @org.id,
              "gh.security_overview_analytics.reconciliation.type": "dependabot_alerts"
            })
          ).once

          timestamps = dbot.lock!
          new_session_started_at = timestamps[:session_started_at]

          assert timestamps[:session_started_at]
          refute_equal session_started_at, new_session_started_at
          refute_equal timestamps[:last_session_started_at], timestamps[:session_started_at]
          assert_dogstats_increment 1, "security_overview_analytics.reconciliation_session.start"
        end
      end
    end
  end
end
