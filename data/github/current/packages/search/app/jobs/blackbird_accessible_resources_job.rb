# typed: strict
# frozen_string_literal: true

class BlackbirdAccessibleResourcesJob < ApplicationJob
  queue_as :blackbird_accessible_resources_job
  retry_on_dirty_exit

  SERVICE = "blackbird"

  retry_on *T.unsafe(GitHub::Config::Redis::REDIS_DOWN_EXCEPTIONS), wait: :polynomially_longer do |_job, error|
    Failbot.report(error, catalog_service: SERVICE)
  end

  # Attempts to enqueue a job with an active lock results in no errors raised or returned.
  # The job is simply not enqueued and the calling code continues.
  locked_by timeout: 180.seconds, key: ->(job) {
    params = job.arguments[0]
    BlackbirdSearch::Redis.key(key_prefix: params[:key_prefix], actor_id: params[:actor].id, session_id: params[:session_id], ip_address: params[:request_user_ip])
  }

  sig do
    params(
      actor: T.any(Bot, User), # The actor making the code search request.
      auth_id: Integer, # The database id of the associated authorization type used to authorize the actor.
      auth_type: Symbol, # The associated authorization type used by the actor.
      expires_at: T.nilable(ActiveSupport::TimeWithZone), # The expiration time for a fine-grained PAT. Only valid for the :user_programmatic_access auth type.
      has_lock: T::Boolean, # Indicates a lock already exists at the time the job is enqueued.
      key_prefix: String, # The key_prefix of the key specified in the request.
      request_id: String, # The GitHub generated request ID.
      request_user_ip: String, # The originating IP address of the request (i.e. the Actor's IP address).
      session_id: String, # The identifier used to uniquely determine the authenticated actor context for lookup in the accessible resources cache. Can be the string form of UserSesssion#id or the hashed value of the access token used in an API request.
      token_kind: String # The kind of token used to authenticate the actor (i.e. API or Web).
    ).void
  end
  def perform(actor:, auth_id:, auth_type:, expires_at:, has_lock:, key_prefix:, request_id:, request_user_ip:, session_id:, token_kind:)
    GitHub.logger.tagged(
      "catalog_service" => SERVICE,
      "code.namespace" => self.class.name,
      "gh.actor.id" => actor.id,
      "gh.request_id" => request_id,
      "request_id" => request_id,
      "gh.auth_type" => auth_type,
      "gh.auth_id" => auth_id,
      "gh.token_kind" => token_kind,
    ) do
      key = BlackbirdSearch::Redis.key(key_prefix: key_prefix, actor_id: actor.id, session_id: session_id, ip_address: request_user_ip)
      mutex = BlackbirdSearch::Redis.mutex(key: key)

      if !has_lock
        begin
          mutex.lock
        rescue GitHub::Redis::Mutex::LockError => e
          # Another process raced and acquired the lock so let that process continue and return.
          return
        end
      end

      begin
        auth_result = BlackbirdSearch::AuthenticationResult.load_auth_result(
          actor: actor,
          auth_id: auth_id,
          auth_type: auth_type,
          expires_at: expires_at,
          request_user_ip: request_user_ip,
          session_id: session_id,
          token_kind: token_kind,
        )

        if auth_result.success?
          BlackbirdSearch::Redis.set(key: key, value: T.must(auth_result.blackbird_actor).accessible_resources.to_proto, expire_sec: 10.minutes)
          GitHub.logger.info("blackbird accessible resources background job set actor")
        else
          GitHub.dogstats.increment("blackbird_accessible_resources_job.load_auth_result", tags: ["auth_type:#{auth_type}"])
          GitHub.logger.error("failed to load blackbird actor", "gh.error.message" => auth_result.error)
        end
      ensure
        mutex.unlock
      end
    end
  end
end
