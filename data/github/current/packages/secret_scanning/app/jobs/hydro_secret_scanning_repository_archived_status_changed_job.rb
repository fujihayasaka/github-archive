# typed: strict
# frozen_string_literal: true

class HydroSecretScanningRepositoryArchivedStatusChangedJob < HydroMessageJob
  include RepositoryHydroMessageJobTenantContext

  queue_as :hydro_secret_scanning_repository_archived_status_changed
  retry_on_dirty_exit

  sig { override.returns(Integer) }
  attr_reader :repository_id

  sig do
    params(
      protobuf: T.untyped,
      headers: T.untyped,
      schema: T.untyped,
      timestamp: T.untyped,
      timestamp_nano: T.untyped,
      message: T.untyped,
      queue: T.untyped
    ).void
  end
  def initialize(protobuf:, headers:, schema:, timestamp:, timestamp_nano:, message:, queue:)
    super

    repository_id, request_id = message.values_at(
      :repository_id,
      :request_id
    )
    @repository_id = T.let(repository_id, Integer)

    GitHub.context.push(repository_id:, request_id:)
    Failbot.push(repository_id:, request_id:)
  end

  sig { void }
  def perform
    if repository = Repositories::Public.get_active_or_deleted(repository_id)
      SecretScanning::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(repository_id: repository_id)
    end
  end

  protected

  sig { override.returns(T::Hash[String, T.untyped]) }
  def logging_context
    super.merge({
      "gh.repo.id": repository_id,
      "gh.repo.archived": message.dig(:is_archived),
      "gh.secret_scanning.source_event": schema,
    })
  end
end
