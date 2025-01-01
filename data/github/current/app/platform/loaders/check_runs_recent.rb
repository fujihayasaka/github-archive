# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class CheckRunsRecent < Platform::Loader
      include Scientist

      def self.load(repository, sha)
        self.for(repository).load(sha)
      end

      def initialize(repository)
        @repository = repository
      end

      def fetch(shas)
        runs = get_runs_for_shas(@repository, shas)
        runs = runs.group_by { |r| r.associated_head_sha }
        runs.default = [].freeze
        runs
      end

      private

      def get_runs_for_shas(repository, head_shas)
        target_max_check_ids = CheckRun.select("max(check_runs.id) as id", "check_suites.head_sha as associated_head_sha", "check_runs.repository_id as repository_id").
          joins("INNER JOIN check_suites ON check_suites.id = check_runs.check_suite_id").
          where(check_suites: { id: CheckSuite.from("(#{latest_workflow_suite_ids(repository, head_shas).to_sql} UNION #{latest_non_workflow_suite_ids(repository, head_shas).to_sql}) subquery").select("*") }).
          where(check_suites: { repository_id: repository.id }).
          where("check_suites.workflow_file_path IS NULL OR check_runs.created_at >= IFNULL(check_suites.started_at, check_suites.created_at)").
          group("check_suites.head_sha", :name, :check_suite_id)

        CheckRun.
          joins("INNER JOIN (#{target_max_check_ids.to_sql}) t on t.id = check_runs.id AND t.repository_id = check_runs.repository_id").
          where(check_runs: { repository_id: repository.id }).
          select(check_run_select, "t.associated_head_sha")
      end

      def latest_workflow_suite_ids(repository, head_shas)
        repository.check_suites.
          where(head_sha: head_shas, hidden: false).
          where.not(workflow_file_path: nil).
          group(:head_sha, :github_app_id, :workflow_file_path, :event).
          select("max(id)")
      end

      def latest_non_workflow_suite_ids(repository, head_shas)
        repository.check_suites.
          where(head_sha: head_shas, workflow_file_path: nil).
          select("id")
      end

      def check_run_select
        columns = CheckRun.column_names - Platform::Loaders::CheckRunText::SUPPORTED_COLUMNS.map(&:to_s)
        columns.map { |col| "check_runs.#{col}" }.join(", ")
      end
    end
  end
end
