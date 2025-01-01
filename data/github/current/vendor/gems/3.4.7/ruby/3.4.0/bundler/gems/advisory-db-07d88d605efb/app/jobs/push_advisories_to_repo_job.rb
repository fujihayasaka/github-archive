# frozen_string_literal: true

class PushAdvisoriesToRepoJob < ApplicationJob
  queue_as :high

  BASE_PATH = "/tmp"
  REPO_DIR_NAME = "advisory_database_repo"
  REPO_PATH = "#{BASE_PATH}/#{REPO_DIR_NAME}".freeze

  UnexpectedDiffError = Class.new(StandardError)
  class GitErrorWrapper < StandardError
    def initialize(message:, backtrace:)
      super(message)
      set_backtrace(backtrace)
    end
  end
  GitBranchProtectionError = Class.new(GitErrorWrapper)
  GitNonZeroExitError = Class.new(GitErrorWrapper)

  retry_on GitNonZeroExitError

  def perform(scope: :unprocessed)
    file_count_old = 0
    instrument_diff_count = false
    # Intentionally not throwing lock error so we don't retry the job if another instance is already running
    lock.wrap do
      git = clone_repo
      file_count_old = file_count

      batched_advisory_ids = AdvisorySyncState.batched_advisory_ids_to_sync(scope: scope)
      batched_advisory_ids.each do |advisory_id_batch|
        successful_syncs = []
        published_at_timestamps = []

        Advisory.preload(
          :sync_state,
          :vulnerabilities,
          :references,
          :cwes,
        ).where(id: advisory_id_batch).find_each do |advisory|
          sync_status = sync_advisory(advisory)
          case sync_status
          when :success
            # Will be marked as successful after commit is pushed
            successful_syncs.push(advisory.sync_state)
          when :failure
            advisory.sync_state.failure!
          end
        end

        # add any untracked files to the index for the diff to pick up
        git.add

        # Cancel if we're touching any files that aren't in the advisories folder
        non_advisory_files = git.diff.stats[:files].keys.reject { |file| file.starts_with?("advisories/") }
        raise(UnexpectedDiffError, "Modified non-advisory files: #{non_advisory_files}") unless non_advisory_files.empty?

        if git.diff.size > AdvisorySyncState::BATCH_SIZE * 2
          raise UnexpectedDiffError, "Diff contains #{git.diff.size} files, more than twice the batch size."
        elsif git.diff.size > 0 # rubocop:disable Style/ZeroLengthPredicate (git.diff doesn't have an empty? method)
          ::GitHub::Telemetry::Logs.logger.info(
            "Preparing to push advisories to repo",
            "gh.advisory_inbox.diff.size": git.diff.size,
            "gh.advisory_inbox.diff.files_size": git.diff.stats[:files].keys.size,
            "gh.advisory_inbox.push_advisories.batch_size": advisory_id_batch.size,
            "gh.advisory_inbox.push_advisories.scope": scope,
          )
          affected_ghsa_ids = git.diff.stats[:files].keys.map { |filename| File.basename(filename, ".json") }
          git.commit(commit_message(affected_ghsa_ids))
          instrument_diff_count = true

          # Don't instrument for stale backfills
          if scope == :unprocessed
            affected_advisories = published_advisories(affected_ghsa_ids:, advisories: successful_syncs.map(&:advisory))
            published_at_timestamps = affected_advisories.map(&:published_at)
          end

          git.push(git.remote, "main")
          ::GitHub::Telemetry::Logs.logger.info "Completed synchronization push"

          if published_at_timestamps.any?
            ReplicationLagInstrumentationJob.perform_later(
              pushed_at: Time.current,
              published_at_timestamps:,
              batch_size: advisory_id_batch.size,
              total_batches: batched_advisory_ids.size,
            )
          end
        end

        # only mark advisories as successful after git transactions
        successful_syncs.each(&:success!)
      end
    rescue Git::Error => error
      if error.is_a?(Git::FailedError) && error.message.match?(/\b(GH006|GH013)\b/)
        # GH006: Protected branch update failed
        # GH013: Repository rule violations found
        error_message = "Branch protection rules prevented advisory update from completing!\n\n#{error.message}"
        wrapped_error_class = GitBranchProtectionError
      else
        error_message = "Git operation failed before advisory update was complete!\n\n#{error.message}"
        wrapped_error_class = GitNonZeroExitError
      end
      wrapped_error = wrapped_error_class.new(message: error_message, backtrace: error.backtrace)
      raise wrapped_error
    ensure
      file_count_new = file_count
      AdvisoryDB.stats.distribution("advisory-database.push_advisories_to_repo_job_old_count", file_count_old)
      AdvisoryDB.stats.distribution("advisory-database.push_advisories_to_repo_job_new_count", file_count_new)
      AdvisoryDB.stats.distribution("advisory-database.push_advisories_to_repo_job_diff_count", file_count_old - file_count_new) if instrument_diff_count
      clean_up_clone
    end

    if lock.unlocked? && AdvisorySyncState.unprocessed.present?
      PushAdvisoriesToRepoJob.perform_later
    end
  end

  private

  def clean_up_clone
    # Delete git data first to prevent git from tracking the rest of the deletions
    git_folder = "#{REPO_PATH}/.git"
    FileUtils.remove_dir(git_folder) if Dir.exist?(git_folder)
    FileUtils.remove_dir(REPO_PATH) if Dir.exist?(REPO_PATH)
  end

  def clone_repo
    ::GitHub::Telemetry::Logs.logger.info(
      "Starting to clone advisory database repo",
      "gh.advisory_inbox.advisory_repo": AdvisoryDB.github_advisories_repo,
    )
    git = Git.clone(
      "https://x-access-token:#{AdvisoryDB.github.access_token}@github.com/#{AdvisoryDB.github_advisories_repo}.git",
      REPO_PATH,
      depth: 1,
    )
    ::GitHub::Telemetry::Logs.logger.info(
      "Finished cloning advisory database repo",
      "gh.advisory_inbox.advisory_repo": AdvisoryDB.github_advisories_repo,
    )
    git.config("user.name", AdvisoryDB.github_app_name)
    git.config("user.email", AdvisoryDB.github_app_email)

    git
  end

  def file_count
    dir = REPO_PATH
    Dir[File.join(dir, "**", "*")].count { |file| File.file?(file) }
  end

  # Returns a list of advisories that changed in the diff
  def published_advisories(affected_ghsa_ids:, advisories:)
    advisories.select { |advisory| affected_ghsa_ids.include?(advisory.ghsa_id) }
  end

  # Calculates a commit message based on the number of advisories that changed in the diff
  def commit_message(ghsa_ids)
    if ghsa_ids.size == 1
      "Publish #{ghsa_ids.first}"
    elsif ghsa_ids.size < 25
      "Publish Advisories\n\n#{ghsa_ids.join("\n")}"
    else
      "Advisory Database Sync"
    end
  end

  def lock
    @lock ||= AdvisoryDB::Lock.new("push_advisories_to_repo")
  end

  def remove_advisory_files(advisory)
    path = "#{REPO_PATH}/#{advisory.repo_file_path}"
    File.delete(path) if File.exist?(path)

    path = if advisory.reviewed?
             path.gsub(Advisory::REVIEWED_FOLDER, Advisory::UNREVIEWED_FOLDER)
           else
             path.gsub(Advisory::UNREVIEWED_FOLDER, Advisory::REVIEWED_FOLDER)
           end
    File.delete(path) if File.exist?(path)
  end

  def sync_advisory(advisory)
    remove_advisory_files(advisory)
    write_advisory_file(advisory)
    :success
  rescue AdvisoryDBToolkit::OSV::Transform::Error => error
    Failbot.report!(error, { ghsa_id: advisory.ghsa_id })
    :failure
  end

  def write_advisory_file(advisory)
    path = "#{REPO_PATH}/#{advisory.repo_file_path}"
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, advisory.repo_file_content)
  end
end
