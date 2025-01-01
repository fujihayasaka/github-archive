# typed: true
# frozen_string_literal: true

class HydroUpdateIssueFieldProjectColumnsJob < HydroMessageJob
  include GitHub::Memoizer
  queue_as :hydro_update_issue_field_project_columns
  METRIC_PREFIX = "gh.projects.hydro_update_issue_field_project_columns_job"

  class ProjectColumnNameInvalidError < StandardError; end
  class ProjectColumnRecordInvalidError < StandardError; end
  class ProjectColumnOwnerMismatchError < StandardError; end

  THROTTLING_ERRORS = [
    Freno::Error,
    Freno::Throttler::Error,
    Freno::Throttler::CircuitOpen,
    Freno::Throttler::WaitedTooLong
  ]

  ALLOWED_TOPICS = [
    "github.v1.IssueFieldUpdate",
    "github.v1.IssueFieldDestroy"
  ]

  UNAVAILABILITY_ERRORS = Resiliency::Response::UnavailableExceptions

  BACKOFF_STRATEGY = T.let(
    { max_retries: 5, delay: :polynomially_longer }.freeze,
    T::Hash[Symbol, T.any(Integer, Symbol)]
  )

  T.unsafe(self).retry_on(*THROTTLING_ERRORS, **BACKOFF_STRATEGY) { |job, error| job.log_failed(error) }
  T.unsafe(self).retry_on(*UNAVAILABILITY_ERRORS, **BACKOFF_STRATEGY) { |job, error| job.log_failed(error) }
  retry_on_dirty_exit { |job, error| job.log_failed(error) }

  READ_BATCH_SIZE = 1000

  sig { void }
  def perform
    return unless FeatureFlag.vexi.enabled?(:project_issue_field_hydro, default: false)
    unless message_valid?
      log_skip(reason: :invalid_message)
      return
    end

    unless valid_topic?
      log_skip(reason: :invalid_topic)
      return
    end

    if sync_action == :destroy && issue_field_exists?
      log_skip(reason: :issue_field_exists)
      return
    end

    if sync_action == :update && !issue_field_exists?
      log_skip(reason: :missing_issue_field)
      return
    end

    GitHub.logger.info("info.message" => "Starting issue field project column sync")

    MemexProjectColumn.includes(:memex_project).where(issue_field_id:).find_in_batches(batch_size: READ_BATCH_SIZE) do |batch|
      batch.each do |project_column|
        if project_column.memex_project&.owner_id != issue_field_owner_id
          log_invalid_column_error(reason: :owner_mismatch, column: project_column)
          Failbot.report(ProjectColumnOwnerMismatchError.new("Unable to sync project column"))
          next
        end

        if sync_action == :destroy
          with_write do
            MemexProjectColumn.throttle do
              project_column.destroy!
            end
          end
        else
          MemexProjectColumn.with_issue_field_sync do
            project_column.name = T.must(issue_field).name

            unless project_column.name_changed?
              GitHub.logger.info("info.message" => "Skipping update, name has not changed")
              next
            end

            unless project_column.valid?
              log_invalid_column_error(reason: :name_invalid, column: project_column)
              Failbot.report(ProjectColumnNameInvalidError.new("Project column name is invalid"))
              next
            end

            with_write do
              MemexProjectColumn.throttle do
                begin
                  project_column.save!
                rescue ActiveRecord::RecordInvalid => e
                  log_invalid_column_error(reason: :save_failed, column: project_column)
                  Failbot.report(ProjectColumnRecordInvalidError.new("Project column record is invalid"))
                  next
                end
              end
            end
          end
        end
      end
    end

    GitHub.logger.info("info.message" => "Finished updating issue field project columns")
    GitHub.dogstats.increment("#{METRIC_PREFIX}.success")
  end

  sig { returns(T.nilable(Integer)) }
  private def issue_field_id
    # because issue_field_id defaults to 0 for project columns, ensure the id is not 0 to avoid potentially destructive behavior for project columns
    id = message.dig(:issue_field, :id)
    id == 0 ? nil : id
  end

  sig { returns(T.nilable(Integer)) }
  private def issue_field_owner_id
    message.dig(:issue_field, :owner_id)
  end

  sig { returns(T.nilable(Integer)) }
  private def actor_id
    message.dig(:actor, :id)
  end

  sig { returns(Symbol) }
  private def sync_action
    return :destroy if topic == "github.v1.IssueFieldDestroy"

    :update
  end

  sig { returns(T.nilable(IssueField)) }
  memoize private def issue_field
    IssueField.find_by(owner_id: issue_field_owner_id, id: issue_field_id)
  end

  private def valid_topic?
    ALLOWED_TOPICS.include?(topic)
  end

  sig { returns(T::Boolean) }
  private def message_valid?
    issue_field_id.present? && issue_field_owner_id.present? && actor_id.present?
  end

  sig { returns(T::Boolean) }
  private def issue_field_exists?
    issue_field.present?
  end

  sig { params(reason: Symbol).void }
  private def log_skip(reason:)
    GitHub.logger.info(
      "info.message" => "Skipping project column issue field sync",
      "gh.job.skip_reason" => reason
    )
    GitHub.dogstats.increment("#{METRIC_PREFIX}.skipped", tags: ["reason:#{reason}"])
  end

  sig { params(reason: Symbol, column: MemexProjectColumn).void }
  private def log_invalid_column_error(reason:, column:)
    GitHub.logger.info(
      "info.message" => "Project column is invalid, skipping sync for column",
      "gh.job.skip_reason" => reason,
      "gh.memex.column.id" => column.id,
      "gh.memex.column.name" => column.name,
      "gh.memex.column.errors" => column.errors.full_messages.to_sentence,
      "gh.memex.project.owner_id" => column.memex_project&.owner_id,
      "gh.issue_field.name" => issue_field ? T.must(issue_field).name : nil,
    )
    GitHub.dogstats.increment("#{METRIC_PREFIX}.invalid_column", tags: ["reason:#{reason}"])
  end

  sig { params(error: T.any(Aqueduct::Worker::JobKilled, StandardError)).void }
  def log_failed(error)
    exception_type = error.class.name&.underscore

    GitHub.logger.info(
      "info.message" => "Project column issue field sync failed",
      "exception.type" => exception_type
    )
    GitHub.dogstats.increment("#{METRIC_PREFIX}.failed", tags: ["error:#{exception_type}"])
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def failbot_log_context
    super.merge({
      "messaging.kafka.source.topic" => topic,
      "gh.actor.id" => actor_id,
      "gh.issue_field.id" => issue_field_id,
      "gh.issue_field.owner_id" => issue_field_owner_id,
    })
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def logging_context
    super.merge({
      "messaging.kafka.source.topic" => topic,
      "gh.actor.id" => actor_id,
      "gh.issue_field.id" => issue_field_id,
      "gh.issue_field.owner_id" => issue_field_owner_id,
    })
  end
end
