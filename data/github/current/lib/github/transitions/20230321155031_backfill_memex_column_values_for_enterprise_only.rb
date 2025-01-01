# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition, checkout the relevant documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/running/
module GitHub
  module Transitions
    class BackfillMemexColumnValuesForEnterpriseOnly < Transition
      #
      # As this transition is only for GHES environments, these batches are set high by default
      #
      READ_BATCH_SIZE = 10000
      WRITE_BATCH_SIZE = 1000

      # This query is setup so it can be re-run and avoid checking for existing column values
      # in the case where a column value is present, this will only replace the json_value column
      # with the new value
      INSERT_COLUMN_VALUE_QUERY = <<-SQL
        INSERT INTO memex_project_column_values
          (
            memex_project_column_id,
            memex_project_item_id,
            value,
            json_value,
            json_value_id,
            memex_project_column_data_type,
            creator_id,
            created_at,
            updated_at
          )
          VALUES :rows
          ON DUPLICATE KEY UPDATE
            value = VALUES(value),
            json_value = VALUES(json_value)
        SQL

      attr_reader :iterator

      def read_batch_size
        @other_args[:read_batch_size] || READ_BATCH_SIZE
      end

      def write_batch_size
        @other_args[:write_batch_size] || WRITE_BATCH_SIZE
      end

      def after_initialize
        return unless GitHub.enterprise?

        min_id = readonly { ApplicationRecord::Domain::Memexes.github_sql.value("SELECT COALESCE(MIN(id), 0) FROM memex_project_items") }
        max_id = readonly { ApplicationRecord::Domain::Memexes.github_sql.value("SELECT COALESCE(MAX(id), 0) FROM memex_project_items") }

        @iterator = ApplicationRecord::Domain::Memexes.github_sql_batched_between(
          start: min_id,
          finish: max_id,
          batch_size: read_batch_size,
        )

        @iterator.add <<-SQL
          -- id must go first for batched between to work properly
          SELECT
            id,
            content_type,
            content_id,
            memex_project_id,
            creator_id,
            created_at,
            updated_at
          FROM memex_project_items
          WHERE id BETWEEN :start AND :last
        SQL
      end

      def perform
        return unless GitHub.enterprise?

        GitHub::SQL::Readonly.new(iterator.batches).each do |rows|
          process(rows)
        end
      end

      private

      def process(rows)
        if verbose?
          item_ids = rows.map(&:first)
          log("#{dry_run? ? "Would have denormalized" : "Denormalizing"} content for memex items between #{item_ids.min} and #{item_ids.max}")
        end

        issue_ids, pull_ids, draft_ids, memex_ids = memex_item_content_ids(rows)
        issues_by_id = issues_hash(issue_ids)
        pull_issues_by_pull_id = pull_issues_hash(pull_ids)
        pulls_by_id = pulls_hash(pull_ids)
        drafts_by_id = drafts_hash(draft_ids)

        repo_ids = (issues_by_id.values + pulls_by_id.values).map(&:second)
        repos_by_id = repos_hash(repo_ids)

        title_column_id_by_memex_id = title_columns_hash(memex_ids)

        new_title_column_values = rows.map do |row|
          title_column_value(
            row,
            issues_by_id,
            pull_issues_by_pull_id,
            pulls_by_id,
            drafts_by_id,
            repos_by_id,
            title_column_id_by_memex_id
          )
        end

        log("Ready to insert #{new_title_column_values.length} new title column values") if verbose?

        new_title_column_values.each_slice(write_batch_size) do |slice|
          MemexProjectColumnValue.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            run_batch_insert(slice)
          end
        end

        milestone_ids = issues_by_id.values.map(&:third).compact
        milestones_by_id = milestones_hash(milestone_ids)

        owner_ids = repos_by_id.values.map(&:third)
        owners_by_id = owners_hash(owner_ids)

        milestone_column_id_by_memex_id = milestone_columns_hash(memex_ids)

        new_milestone_column_values = rows.map do |row|
          milestone_column_value(
            row,
            issues_by_id,
            pull_issues_by_pull_id,
            milestones_by_id,
            repos_by_id,
            owners_by_id,
            milestone_column_id_by_memex_id
          )
        end.compact

        log("Ready to insert #{new_milestone_column_values.length} new milestone column values") if verbose?

        new_milestone_column_values.each_slice(write_batch_size) do |slice|
          MemexProjectColumnValue.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            run_batch_insert(slice)
          end
        end
      end

      def run_batch_insert(new_rows)
        return if dry_run?

        result = ApplicationRecord::Domain::Memexes.github_sql.run(
          INSERT_COLUMN_VALUE_QUERY,
          rows: GitHub::SQL::ROWS(new_rows)
        )

        log("Created #{result.affected_rows} new column values in database") if verbose?
      end

      def memex_item_content_ids(rows)
        issue_ids = []
        pull_ids = []
        draft_ids = []
        memex_ids = Set.new

        rows.each do |row|
          _, content_type, content_id, memex_id = row
          issue_ids << content_id if content_type == "Issue"
          pull_ids << content_id if content_type == "PullRequest"
          draft_ids << content_id if content_type == "DraftIssue"
          memex_ids.add(memex_id)
        end

        [issue_ids, pull_ids, draft_ids, memex_ids.to_a]
      end

      def issues_hash(issue_ids)
        return {} if issue_ids.empty?

        ActiveRecord::Base.connected_to(role: :reading) do
          issues = ApplicationRecord::Domain::IssuesPullRequests.github_sql.results(<<-SQL, issue_ids: issue_ids)
            SELECT id, repository_id, milestone_id, title, number, state, state_reason
            FROM issues
            WHERE id IN :issue_ids
          SQL

          issues.index_by(&:first)
        end
      end

      def pull_issues_hash(pull_ids)
        return {} if pull_ids.empty?

        ActiveRecord::Base.connected_to(role: :reading) do
          pull_issues = ApplicationRecord::Domain::IssuesPullRequests.github_sql.results(<<-SQL, pull_ids: pull_ids)
            SELECT id, repository_id, milestone_id, title, number, state, state_reason, pull_request_id
            FROM issues
            WHERE pull_request_id IN :pull_ids
          SQL

          pull_issues.index_by(&:last)
        end
      end

      def pulls_hash(pull_ids)
        return {} if pull_ids.empty?

        ActiveRecord::Base.connected_to(role: :reading) do
          pulls = ApplicationRecord::Domain::IssuesPullRequests.github_sql.results(<<-SQL, pull_ids: pull_ids)
            SELECT id, repository_id, reviewable_state, merged_at
            FROM pull_requests
            WHERE id IN :pull_ids
          SQL

          pulls.index_by(&:first)
        end
      end

      def milestones_hash(milestone_ids)
        return {} if milestone_ids.empty?

        ActiveRecord::Base.connected_to(role: :reading) do
          milestones = ApplicationRecord::Domain::IssuesPullRequests.github_sql.results(<<-SQL, milestone_ids: milestone_ids)
            SELECT id, number, state, title, due_on
            FROM milestones
            WHERE id IN :milestone_ids
          SQL

          milestones.index_by(&:first)
        end
      end

      def drafts_hash(draft_ids)
        return {} if draft_ids.empty?

        ActiveRecord::Base.connected_to(role: :reading) do
          drafts = ApplicationRecord::Domain::Memexes.github_sql.results(<<-SQL, draft_ids: draft_ids)
            SELECT id, title
            FROM draft_issues
            WHERE id IN :draft_ids
          SQL

          drafts.index_by(&:first)
        end
      end

      def repos_hash(repo_ids)
        return {} if repo_ids.empty?

        ActiveRecord::Base.connected_to(role: :reading) do
          repos = ApplicationRecord::Domain::Repositories.github_sql.results(<<-SQL, repo_ids: repo_ids)
            SELECT id, name, owner_id
            FROM repositories
            WHERE id IN :repo_ids
          SQL

          repos.index_by(&:first)
        end
      end

      def owners_hash(owner_ids)
        return {} if owner_ids.empty?

        ActiveRecord::Base.connected_to(role: :reading) do
          owners = ApplicationRecord::Domain::Users.github_sql.results(<<-SQL, owner_ids: owner_ids)
            SELECT id, login
            FROM users
            WHERE id IN :owner_ids
          SQL

          owners.index_by(&:first)
        end
      end

      # Returns Hash<Integer, Integer> where for a given entry the key is a MemexProject ID and the
      # value is the MemexProjectColumn ID for the Title column in that memex.
      def title_columns_hash(memex_ids)
        return {} if memex_ids.empty?

        # As a special (rather than generic) data type, title is guaranteed to be unique.
        data_type = MemexProjectColumn.data_types[:title]

        ActiveRecord::Base.connected_to(role: :reading) do
          columns = ApplicationRecord::Domain::Memexes.github_sql.results(<<-SQL, memex_ids: memex_ids, data_type: data_type)
            SELECT id, memex_project_id
            FROM memex_project_columns
            WHERE memex_project_id IN :memex_ids AND data_type = :data_type
          SQL

          columns.reduce({}) do |memo, col|
            column_id, memex_id = col
            memo[memex_id] = column_id
            memo
          end
        end
      end

      # Returns Hash<Integer, Integer> where for a given entry the key is a MemexProject ID and the
      # value is the MemexProjectColumn ID for the Milestone column in that memex.
      def milestone_columns_hash(memex_ids)
        return {} if memex_ids.empty?

        # As a special (rather than generic) data type, milestone is guaranteed to be unique.
        data_type = MemexProjectColumn.data_types[:milestone]

        ActiveRecord::Base.connected_to(role: :reading) do
          columns = ApplicationRecord::Domain::Memexes.github_sql.results(<<-SQL, memex_ids: memex_ids, data_type: data_type)
            SELECT id, memex_project_id
            FROM memex_project_columns
            WHERE memex_project_id IN :memex_ids AND data_type = :data_type
          SQL

          columns.reduce({}) do |memo, col|
            column_id, memex_id = col
            memo[memex_id] = column_id
            memo
          end
        end
      end

      def milestone_column_value(row, issues_by_id, pull_issues_by_pull_id, milestones_by_id, repos_by_id, owners_by_id, milestone_column_id_by_memex_id)
        item_id, content_type, content_id, memex_id, creator_id, created_at, updated_at = row
        return nil if content_type == "DraftIssue"

        _, repo_id, milestone_id, _, _, _, _, _ = content_type == "Issue" ? issues_by_id[content_id] : pull_issues_by_pull_id[content_id]

        return nil unless milestone_id.present?

        _, number, state, title, due_on = milestones_by_id[milestone_id]
        _, repo_name, owner_id = repos_by_id[repo_id]
        _, owner_name = owners_by_id[owner_id]

        due_date = if due_on
          due_on.utc.to_date
        else
          nil
        end

        json_value = {
          type: "Milestone",
          value: {
            id: milestone_id,
            number: number,
            state: state,
            title: title,
            url: "/#{owner_name}/#{repo_name}/milestone/#{number}",
            dueDate: due_date,
            repoNameWithOwner: "#{owner_name}/#{repo_name}"
          }
        }

        [
          milestone_column_id_by_memex_id[memex_id],
          item_id,
          milestone_id,
          json_value.to_json,
          milestone_id,
          2,
          creator_id,
          created_at,
          updated_at
        ]
      end

      def title_column_value(row, issues_by_id, pull_issues_by_pull_id, pulls_by_id, drafts_by_id, repos_by_id, title_column_id_by_memex_id)
        _, content_type = row

        if content_type == "DraftIssue"
          draft_issue_title_column_value(row, drafts_by_id, title_column_id_by_memex_id)
        else
          issue_or_pull_title_column_value(
            row,
            issues_by_id,
            pull_issues_by_pull_id,
            pulls_by_id,
            repos_by_id,
            title_column_id_by_memex_id
          )
        end
      end

      def draft_issue_title_column_value(row, drafts_by_id, title_column_id_by_memex_id)
        item_id, _, content_id, memex_id, creator_id, created_at, updated_at = row
        _, title = drafts_by_id[content_id]

        [
          title_column_id_by_memex_id[memex_id],
          item_id,
          title,
          {
            title: {
              raw: title,
              html: GitHub::Goomba::MemexTextColumnPipeline.to_html(title)
            }
          }.to_json,
          GitHub::SQL::NULL,
          4,
          creator_id,
          created_at,
          updated_at
        ]
      end

      def issue_or_pull_title_column_value(row, issues_by_id, pull_issues_by_pull_id, pulls_by_id, repos_by_id, title_column_id_by_memex_id)
        item_id, content_type, content_id, memex_id, creator_id, created_at, updated_at = row
        issue_id, repo_id, _, title, number, issue_state, state_reason, _ = content_type == "Issue" ? issues_by_id[content_id] : pull_issues_by_pull_id[content_id]
        pull = pulls_by_id[content_id] if content_type == "PullRequest"
        _, _, reviewable_state, merged_at = pull if pull
        _, _, repo_owner_id = repos_by_id[repo_id]

        id_based_repository_url = "#{GitHub.scheme}://#{GitHub.host_name}/#{repo_owner_id}/#{repo_id}"

        json_value = {
          title: {
            raw: title,
            html: GitHub::Goomba::TitleMarkdownFilter.call(title)
          },
          number: number,
          issueId: issue_id,
          state: issue_or_pull_state(pull, issue_state, merged_at),
          isDraft: reviewable_state && reviewable_state == PullRequest.reviewable_states[:draft],
          url: "#{id_based_repository_url}/#{pull ? "pull" : "issues"}/#{number}",
        }.compact

        unless pull
          # If the suggestion isn't a PR, include the issue state_reason value as it's enum
          # representation (nil is fine to store here)
          state_reason_value = issue_state_reason_value(state_reason)
          json_value = json_value.merge({ stateReason: state_reason_value })
        end

        [
          title_column_id_by_memex_id[memex_id],
          item_id,
          title.force_encoding("UTF-8"),
          json_value.to_json,
          GitHub::SQL::NULL,
          4,
          creator_id,
          created_at,
          updated_at
        ]
      end

      def issue_state_reason_value(state_reason)
        return "not_planned" if state_reason == 1
        return "reopened" if state_reason == 2

        nil
      end

      def issue_or_pull_state(pull, issue_state, merged_at)
        return "open" if pull && issue_state == "open"
        return "merged" if pull && merged_at.present?
        return "closed" if pull

        issue_state
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do |write|
      options[:write] = write
    end

    opts.on("-v", "--verbose", "Log verbose output") do |verbose|
      options[:verbose] = verbose
    end

    opts.on("--start_id ID", Integer, "ID to start processing") do |start_id|
      options[:start_id] = start_id
    end

    opts.on("--end_id ID", Integer, "ID to end processing") do |end_id|
      options[:end_id] = end_id
    end

    opts.on("--read_batch_size SIZE", Integer, "Number of rows to read at a time") do |read_batch_size|
      options[:read_batch_size] = read_batch_size
    end

    opts.on("--write_batch_size SIZE", Integer, "Number of rows to write at a time") do |write_batch_size|
      options[:write_batch_size] = write_batch_size
    end

    opts.on("-n", "--workers COUNT", Integer, "Worker count") do |workers|
      options[:workers] = workers
    end
  end.parse!

  options[:workers] ||= 1
  options[:dry_run] = !options[:write]
end
