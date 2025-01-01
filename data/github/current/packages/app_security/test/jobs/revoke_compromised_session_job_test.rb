# typed: true
# frozen_string_literal: true

require "test_helper"

unless GitHub.single_business_environment?
  class RevokeCompromisedSessionJobTest < GitHub::TestCase
    include DogstatsTestHelpers

    test "runs revoke job for given session" do
      Timecop.freeze do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        session = create(:user_session)
        assert_nil session.revoked_at

        RevokeCompromisedSessionJob.perform_now(session.id)
        session.reload

        assert_equal session.revoked_at.to_i, Time.now.to_i
        assert_equal session.revoked_reason, "compromised_session"
        assert_dogstats_increment 1, "user_session.risk_revocation.revoked"
      end
    end

    test "does not allow concurrent jobs for the same session" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      session = create(:user_session)

      Timecop.freeze do
        assert_enqueued_jobs 1, only: RevokeCompromisedSessionJob do
          RevokeCompromisedSessionJob.enqueue(session.user_id, session.id)
          RevokeCompromisedSessionJob.enqueue(session.user_id, session.id)
          RevokeCompromisedSessionJob.perform_later(session.id)
          # the "extra" attempts are not retried
          RevokeCompromisedSessionJob.any_instance.expects(:retry_job).never
        end
      end
    end

    test "does allow multiple queued jobs for different sessions" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      session_a = create(:user_session)
      session_b = create(:user_session)

      Timecop.freeze do
        assert_enqueued_jobs 2, only: RevokeCompromisedSessionJob do
          RevokeCompromisedSessionJob.enqueue(session_a.user_id, session_a.id)
          RevokeCompromisedSessionJob.enqueue(session_b.user_id, session_b.id)
          RevokeCompromisedSessionJob.enqueue(session_a.user_id, session_a.id)
          RevokeCompromisedSessionJob.enqueue(session_b.user_id, session_b.id)
        end
      end
    end

    test "keeps track of session count per user" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      session_a = create(:user_session)
      session_b = create(:user_session, user: session_a.user)
      session_a.user.enable_feature(:session_update_analysis_revoke)

      Timecop.freeze do
        RevokeCompromisedSessionJob.perform_now(session_a.id)
        count = GitHub::Authentication::KV.store.get(RevokeCompromisedSessionJob.revoked_count_key(session_a.user_id)).value { nil }&.to_i
        assert_equal count, 1
        RevokeCompromisedSessionJob.perform_now(session_b.id)
        count = GitHub::Authentication::KV.store.get(RevokeCompromisedSessionJob.revoked_count_key(session_a.user_id)).value { nil }&.to_i
        assert_equal count, 2
      end
    end

    test "doesn't error if session is revoked" do
      Timecop.freeze do
        session = create(:user_session)
        session.revoke(:logout)

        session.reload
        assert_equal session.revoked_at.to_i, Time.now.to_i
        assert_equal session.revoked_reason, "logout"

        RevokeCompromisedSessionJob.perform_now(session.id)

        session.reload
        assert_equal session.revoked_at.to_i, Time.now.to_i
        assert_equal session.revoked_reason, "logout"
        assert_dogstats_increment 1, "user_session.risk_revocation.already_revoked"
      end
    end

    test "doesn't error if session is missing" do
      session = create(:user_session)
      session_id = session.id
      session.destroy
      RevokeCompromisedSessionJob.perform_now(session_id)
      assert_dogstats_increment 1, "user_session.risk_revocation.not_found"
    end
  end
end
