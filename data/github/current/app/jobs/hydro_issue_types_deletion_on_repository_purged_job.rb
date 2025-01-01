# typed: true
# frozen_string_literal: true

class HydroIssueTypesDeletionOnRepositoryPurgedJob < Repositories::RepositoryHydroMessageJob
  extend T::Sig

  include Repositories::Domain::Provider


  queue_as :hydro_issue_types_deletion_on_repository_purged
  retry_on_dirty_exit

  class TooManyRecords < StandardError; end

  BATCH_SIZE = BatchedJob::BATCH_SIZE

  sig { void }
  def perform
    return unless delete_issue_types_on_repository_purged?

    return unless repositories_domain.by_id(repository_id).nil?

    with_primaries([ApplicationRecord::IssuesPullRequests]) do
      records = RepositoryIssueType.where(repository_id: repository_id)

      record_count = records.size
      if record_count > BATCH_SIZE
        error = TooManyRecords.new("Too many records to delete: #{record_count}")
        Failbot.report(error)
      end

      destroyed = 0
      not_destroyed = 0
      records.each do |record|
        if record.destroy
          destroyed += 1
        else
          not_destroyed += 1

          GitHub.logger.warn(
            "Record failed to be destroyed", {
              "code.namespace" => "HydroIssueTypesDeletionOnRepositoryPurgedJobx",
              "code.function" => "perform",
              "record_id" => record.id,
              "repository_id" => repository_id,
              "error" => record.errors.full_messages.join(","),
            }
          )
        end
      end
      GitHub.dogstats.count("hydro_issues_types_deletion_on_repository_purged.records_destroyed", destroyed)
      GitHub.dogstats.count("hydro_issues_types_deletion_on_repository_purged.records_not_destroyed", not_destroyed) if not_destroyed > 0
    end
  end

  sig { returns(T::Boolean) }
  def delete_issue_types_on_repository_purged?
    if GitHub.flipper[:hydro_issue_types_deletion_on_repository_purged_kill_switch].enabled?
      log_skip_reason("Kill switch enabled")
      return false
    end

    true
  end
  private :delete_issue_types_on_repository_purged?

  sig { params(reason: String).void }
  def log_skip_reason(reason)
    GitHub.logger.info("Hydro issue types deletion on repository purged job", {
      "code.namespace" => self.class.name,
      "gh.repo.id" => repository_id,
      "gh.job.skip_reason" => reason,
    })
  end
  private :log_skip_reason
end
