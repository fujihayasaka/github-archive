# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class HydroIssueTypesDeletionOnUserDestroyedJob < HydroMessageJob
  queue_as :hydro_issue_types_deletion_on_user_destroyed

  retry_on_dirty_exit
  retry_on *T.unsafe(Resiliency::Response::UnavailableExceptions)
  retry_on Freno::Throttler::Error, Freno::Error, Freno::Throttler::WaitedTooLong

  class TooManyRecords < StandardError; end

  BATCH_SIZE = BatchedJob::BATCH_SIZE

  sig { returns(T::Hash[Symbol, String]) }
  attr_reader :user

  sig { params(protobuf: T.untyped, headers: T.untyped, schema: T.untyped, timestamp: T.untyped, timestamp_nano: T.untyped, message: T.untyped, queue: T.untyped).void }
  def initialize(protobuf:, headers:, schema:, timestamp:, timestamp_nano:, message:, queue:)
    super

    @user = message[:user]
  end

  sig { void }
  def perform
    return unless user[:type]&.to_sym == :ORGANIZATION
    return unless delete_issue_types_on_user_destroyed?

    owner_id = user[:id].to_i

    return unless Users.domain.by_id(owner_id).nil?

    with_primaries([ApplicationRecord::IssuesPullRequests]) do
      records = IssueType.where(owner_id: owner_id)

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
            "Dependent record failed to be destroyed", {
              "code.namespace" => "HydroIssueTypesDeletionOnUserDestroyedJob",
              "code.function" => "perform",
              "record_id" => record.id,
              "owner_id" => owner_id,
              "error" => record.errors.full_messages.join(","),
            }
          )
        end
      end
      GitHub.dogstats.count("hydro_issues_types_deletion_on_user_destroyed.records_destroyed", destroyed)
      GitHub.dogstats.count("hydro_issues_types_deletion_on_user_destroyed.records_not_destroyed", not_destroyed) if not_destroyed > 0
    end
  end

  private

  sig { returns(T::Boolean) }
  def delete_issue_types_on_user_destroyed?
    if GitHub.flipper[:hydro_issue_types_deletion_on_user_destroyed_kill_switch].enabled?
      log_skip_reason("Kill switch enabled")
      return false
    end

    true
  end

  sig { params(reason: String).void }
  def log_skip_reason(reason)
    GitHub.logger.info("Hydro issue types deletion on user destroyed job", {
      "code.namespace" => self.class.name,
      "gh.user.id" => user[:id],
      "gh.job.skip_reason" => reason,
    })
  end
end
