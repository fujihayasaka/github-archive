# typed: true
# frozen_string_literal: true

class RevokeCompromisedSessionJob < ApplicationJob
  queue_as :revoke_compromised_session

  retry_on_dirty_exit

  # We only want one of these jobs pending/running per session
  locked_by timeout: 10.minutes, key: ->(job) { job.build_lock_key }


  def self.jitter
    rand(5.minutes)
  end

  def self.with_write(&block)
    ActiveRecord::Base.connected_to(role: :writing, &block)
  end

  def self.pending_revocation_key(id)
    "pending-revoke-session:#{id}"
  end

  def self.revoked_count_key(id)
    "abuse-session-revoked-count:#{id}"
  end

  def self.count_expiration
    Time.now + 2.weeks
  end

  # Ensure that the enqueued job is performed some time after the user_session is flagged
  def self.enqueue(user_id, session_id)
    delay = self.jitter
    delay_time = Time.now + delay
    # using KV to check if any password updates happen during the delay period
    with_write do
      GitHub::Authentication::KV.store.set(self.pending_revocation_key(user_id), "true", expires: delay_time)
    end
    self.set(wait_until: delay_time).perform_later(session_id)
  end

  def perform(session_id)
    return unless GitHub.sign_in_analysis_enabled?
    session = UserSession.find_by(id: session_id)

    if session.nil?
      log_outcome(:not_found, session_id)
      return
    end

    revoked_sessions_count = GitHub::Authentication::KV.store.get(RevokeCompromisedSessionJob.revoked_count_key(session.user_id)).value { nil }.to_i
    new_revoked_count = revoked_sessions_count + 1

    if session.revoked?
      log_outcome(:already_revoked, session_id, session, revoked_sessions_count)
      return
    end

    with_write do
      session.revoke(:compromised_session)
      GitHub::Authentication::KV.store.set(RevokeCompromisedSessionJob.revoked_count_key(session.user_id), new_revoked_count.to_s, expires: RevokeCompromisedSessionJob.count_expiration)
    end
    log_outcome(:revoked, session_id, session, new_revoked_count)
  end

  def log_outcome(result, session_id, session = nil, count = 0)
    GitHub.dogstats.increment("user_session.risk_revocation.#{result}")
    GitHub.dogstats.distribution("user_session.risk_revocation.revoked_count", count, tags: ["result:#{result}"])

    log_data = {
      "code.function" => "revoke_compromised_session_job.log_outcome",
      "revoke_compromised_session_job.result" => result,
      "revoke_compromised_session_job.session_id" => session_id,
      "revoke_compromised_session_job.total_revoked_sessions_count" => count,
    }
    log_data = log_data.merge(session.log_hash) if session.present?

    GitHub.logger.info(log_data)
  end

  def build_lock_key
    "revoke-session:#{arguments[0]}"
  end
end
