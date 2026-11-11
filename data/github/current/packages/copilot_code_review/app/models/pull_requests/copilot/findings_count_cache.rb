# typed: strict
# frozen_string_literal: true

class PullRequests::Copilot::FindingsCountCache
  extend T::Generic
  include GitHub::RemoteCache::Preset

  SourceKeyType = type_member { { fixed: Integer } }
  SourceValueType = type_member { { fixed: Integer } }

  # Fetches the cached findings count for a pull request.
  # On cache miss, queries the Copilot API when user context is available.
  sig do
    params(
      pull_request: PullRequest,
      user: T.nilable(User),
      user_session: T.nilable(UserSession),
      remote_ip: T.nilable(String),
    ).returns(Integer)
  end
  def self.count_for(pull_request, user: nil, user_session: nil, remote_ip: nil)
    new(pull_request.id).fetch do
      next 0 unless user && user_session

      PullRequests::Copilot::FindingsLoader.new(
        user: user,
        user_session: user_session,
        remote_ip: remote_ip,
        entry_point: :code_review_findings_count,
      ).fetch_findings_count(pull_request)
    rescue CopilotSessions::CopilotApiToken::IntegrationUnavailableError, CopilotAPI::Error
      0
    end
  end

  sig { params(pull_request_id: Integer).void }
  def initialize(pull_request_id)
    @pull_request_id = pull_request_id
  end

  sig { override.returns(Symbol) }
  def cache_key_name
    :copilot_findings_count
  end

  sig { override.params(source_key: SourceKeyType).returns(String) }
  def cache_key_id(source_key)
    "v1:pr:#{source_key}"
  end

  sig { override.returns(T::Array[SourceKeyType]) }
  def source_keys
    [@pull_request_id]
  end

  sig { override.returns(Integer) }
  def ttl
    1.day.to_i
  end

  sig { override.returns(T::Boolean) }
  def enabled?
    true
  end

  sig { override.returns(SourceValueType) }
  def fallback
    0
  end

  sig { override.returns(T::Array[T.class_of(StandardError)]) }
  def resilience_error_types
    GitHub::ResilienceMixin::DATABASE_ERROR_TYPES_ALLOWLIST
  end

  sig { override.returns(T.class_of(GitHub::RemoteCache::NumericSerializer)) }
  def serializer
    GitHub::RemoteCache::NumericSerializer
  end

  sig { override.returns(T.nilable(GitHub::RemoteCache::StalenessObserver[SourceValueType])) }
  def staleness_observer
    GitHub::RemoteCache::PrimitiveValueStalenessObserver
  end

  sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
  def rollout_mode
    GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
  end

  private

  sig { override.returns(GitHub::RemoteCache::Client) }
  def cache_client
    PullRequests::Cache.client
  end
end
