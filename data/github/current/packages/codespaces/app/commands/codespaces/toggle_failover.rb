# typed: strict
# frozen_string_literal: true

module Codespaces
  class ToggleFailover < Codespaces::Command
    extend T::Sig

    class Unavailable < Codespaces::Error; end

    CODESPACES_REPOSITORY_NWO = "github/codespaces"
    REDIRECT_TYPES = T.let(%w(create creates resume resumes).freeze, T::Array[String])

    sig { returns(Codespaces::VscsServiceStamp) }
    attr_reader :stamp

    sig { returns(GitHub::Redis::Mutex) }
    attr_reader :mutex

    sig { returns(T::Boolean) }
    attr_reader :redirect

    sig { returns(T.nilable(String)) }
    attr_reader :actor

    sig { returns(T.nilable(String)) }
    attr_reader :only

    # Let the lock timeout before the request times out
    LOCK_TIMEOUT = T.let(GitHub.default_request_timeout - 2, Integer)

    sig { params(stamp: Codespaces::VscsServiceStamp, redirect: T::Boolean, only: T.nilable(String), mutex: GitHub::Redis::Mutex, codespaces_repository: T.nilable(Repository), actor: T.nilable(String)).void }
    def initialize(stamp:, redirect:, only: nil, mutex: GitHub::Redis::Mutex.new("codespaces.failover.#{stamp.vscs_target}", expiration: LOCK_TIMEOUT), codespaces_repository: nil, actor: nil)
      @stamp = stamp
      @mutex = mutex
      @redirect = redirect
      @only = only
      @codespaces_repository = T.let(codespaces_repository || Repository.with_name_with_owner(CODESPACES_REPOSITORY_NWO), Repository)
      @actor = actor
    end

    sig { override.void }
    def perform
      # Push the actor into the context so that the feature flag actions are attributed properly
      if actor
        GitHub.context.push(actor:)
        Audit.context.push(actor:)
      end
      author = actor ? "@#{actor}" : "automation"

      begin
        mutex.lock do
          begin
            validate!
            toggle_dotcom_failover
          rescue => e
            GitHub::Chatterbox.client.say!(
              "#codespaces-ops",
              ":red-error: #{redirect ? "Enabling" : "Disabling"} regional failover for #{stamp.region} in #{stamp.vscs_target} by #{author} encountered an unexpected error: #{e.message}",
            )
            raise e
          end
          GitHub::Chatterbox.client.say!(
            "#codespaces-ops",
            ":fluent-globe_with_meridians: #{redirect ? "Enabling" : "Disabling"} regional failover for #{stamp.region} in #{stamp.vscs_target} by #{author} succeeded.",
          )
        end
      rescue GitHub::Redis::Mutex::LockError
        GitHub::Chatterbox.client.say!(
          "#codespaces-ops",
          ":red-error: #{redirect ? "Enabling" : "Disabling"} regional failover for #{stamp.region} in #{stamp.vscs_target} by #{author} failed. Lock is held, failover may already be in progress.",
        )
        raise Unavailable, "failover may already be in progress for this vscs_target"
      end
    end

    private

    sig { void }
    def validate!
      return unless redirect

      availability_user = if actor
        User.find_by_login(actor) || User.ghost
      else
        User.ghost
      end
      return if availability_user.ghost? && !stamp.target_config.production?

      raise Unavailable, "no backup regions available" if stamp.available_backups(user: availability_user).blank?

      if only && !REDIRECT_TYPES.include?(only)
        raise ArgumentError, "`only` must specify one of #{REDIRECT_TYPES.join(', ')}"
      end
    end

    sig { returns(T::Boolean) }
    def redirect_creates?
      only.nil? || T.must(only).start_with?("create")
    end

    sig { returns(T::Boolean) }
    def redirect_resumes?
      only.nil? || T.must(only).start_with?("resume")
    end

    sig { void }
    def toggle_dotcom_failover
      ActiveRecord::Base.connected_to(role: :writing) do
        if redirect
          stamp.failover(creates: redirect_creates?, resumes: redirect_resumes?)
        else
          stamp.failback(creates: redirect_creates?, resumes: redirect_resumes?)
        end
      end
    end

    sig { returns(T::Array[String]) }
    def dd_tags
      super.concat(["vscs_target:#{stamp.vscs_target}", "location:#{stamp.region.id}"])
    end
  end
end
