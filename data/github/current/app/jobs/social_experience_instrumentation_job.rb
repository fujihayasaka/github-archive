# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class SocialExperienceInstrumentationJob < ApplicationJob
  queue_as :social_experience_instrumentation

  retry_on_dirty_exit

  discard_on ActiveRecord::RecordNotFound

  rescue_from(ActiveJob::DeserializationError) do |exception|
    GitHub.logger.info("ActiveJob::DeserializationError", {
      "error": exception.message,
      "code.namespace": "SocialExperienceInstrumentationJob",
      "code.function": "publish_query",
      "gh.request_id": GitHub.context[:request_id],
      "gh.controller": GitHub.context[:controller],
      "gh.action": GitHub.context[:controller_action],
      "gh.method": GitHub.context[:method],
      "gh.from": GitHub.context[:from],
      "gh.catalog_service": GitHub.context[:catalog_service],
      "gh.request_category": GitHub.context[:category],
    })
  end

  UNSCOPED_QUERY = "UNSCOPED"
  NOT_CROSS_ORG = "NO"
  MAYBE_CROSS_ORG = "MAYBE"
  IS_CROSS_ORG_UNKNOWN = "UNKNOWN"

  def initialize(*args, **kwargs)
    @request_id = GitHub.context[:request_id]
    @request_method = GitHub.context[:method] || GitHub.context[:request_method]
    @controller = GitHub.context[:controller]
    @action = GitHub.context[:controller_action]
    @from = GitHub.context[:from]
    @catalog_service = GitHub.context[:catalog_service]
    @request_category = GitHub.context[:category]

    super(*T.unsafe(args), **kwargs)
  end

  def perform(redacted_unique_queries = [])
    GitHub.logger.info("Processing #{redacted_unique_queries.count} queries", {
      "code.namespace": "SocialExperienceInstrumentationJob",
      "code.function": "perform",
      "gh.request_id": @request_id,
      "gh.controller": @controller,
      "gh.action": @controller_action,
      "gh.method": @request_method,
      "gh.from": @from,
      "gh.catalog_service": @catalog_service,
      "gh.request_category": @request_category,
    })

    org_ids_for_request = []
    redacted_unique_queries.each do |redacted_query|
      if redacted_query[:redacted_sql].start_with?("INSERT INTO")
        table_name, columns, rows = GitHub::SQL::QueryTracking.parse_insert_query(redacted_query[:redacted_sql])
        if relevant_tables.include?(table_name)
          org_ids_for_query = guess_org_ids_from_insert_query(table_name, columns, rows)
          org_ids_for_request.concat(org_ids_for_query)
          record_maybe_cross_org_query(redacted_query, org_ids_for_query)
        else
          record_no_cross_org_queries_for_query(redacted_query)
        end
      elsif redacted_query[:redacted_sql].start_with?("SELECT")
        match = redacted_query[:redacted_sql].match(/SELECT.+FROM\s+(?<tables_str>.+?)\s+WHERE\s+(?<where_clause>.+)/m)
        if !match.nil? && relevant_tables.any? { |relevant_tables| match[:tables_str].include?(relevant_tables) }
          org_ids_for_query = guess_org_ids_for_select_and_delete(match[:tables_str], match[:where_clause])
          org_ids_for_request.concat(org_ids_for_query)
          record_maybe_cross_org_query(redacted_query, org_ids_for_query)
        else
          record_no_cross_org_queries_for_query(redacted_query)
        end
      elsif redacted_query[:redacted_sql].start_with?("DELETE")
        match = redacted_query[:redacted_sql].match(/DELETE.+FROM\s+(?<tables_str>.+?)\s+WHERE\s+(?<where_clause>.+)/m)
        if relevant_tables.any? { |relevant_tables| match[:tables_str].include?(relevant_tables) }
          org_ids_for_query = guess_org_ids_for_select_and_delete(match[:tables_str], match[:where_clause])
          org_ids_for_request.concat(org_ids_for_query)
          record_maybe_cross_org_query(redacted_query, org_ids_for_query)
        else
          record_no_cross_org_queries_for_query(redacted_query)
        end
      elsif redacted_query[:redacted_sql].start_with?("UPDATE")
        # todo: find org_ids for UPDATE queries
      end
    end

    if org_ids_for_request.compact.uniq.length < 2
      record_no_cross_org_queries_for_request
    end
  end

  private

  def guess_org_ids_for_select_and_delete(table_str, where_clause)
    org_ids_for_query = []

    if (where_clause.include?("`users`.`type` = 'Organization'") && match = where_clause.match(/`users`.`id` IN \((.+)\)/)) ||
        (match = where_clause.match(/`organization_id` IN \((.+)\)/)) ||
        (table_str.include?("`user_emails`") && match = where_clause.match(/`user_emails`.`user_id` = (\d+)/)) ||
        (table_str.include?("`user_emails`") && match = where_clause.match(/`user_emails`.`user_id` IN \((.+)\)/)) ||
        (where_clause.include?("`users`.`type` = 'Organization'") && match = where_clause.match(/`users`.`id` = (\d+)/)) ||
        (match = where_clause.match(/`repositories`.`owner_id` IN \((.+)\)/)) ||
        (match = where_clause.match(/`repositories`.`owner_id` = (\d+)/)) ||
        (match = where_clause.match(/`organization_id` = (\d+)/)) ||
        (table_str.include?("`business_user_accounts`") && match = where_clause.match(/`business_user_accounts`.`user_id` IN \((.+)\)/)) ||
        (table_str.include?("`business_user_accounts`") && match = where_clause.match(/`business_user_accounts`.`user_id` = (\d+)/))
      org_ids_for_query.concat(match[1].split(",").map(&:to_i))
    end

    if (match = where_clause.match(/`repository_id` IN \((.+)\)/)) ||
        (match = where_clause.match(/`repository_id` = (\d+)/)) ||
        (match = where_clause.match(/`repositories`.`id` IN \((.+)\)/)) ||
        (match = where_clause.match(/`repositories`.`id` = (\d+)/)) ||
        (table_str.include?("`repository_advisories`") && match = where_clause.match(/`repository_advisories`.`workspace_repository_id` IN \((.+)\)/)) ||
        (table_str.include?("`repository_advisories`") && match = where_clause.match(/`repository_advisories`.`workspace_repository_id` = (\d+)/))
      repo_ids = match[1].split(",").map(&:to_i)
      org_ids_for_query.concat(Repository.where(id: repo_ids).map(&:owner_id))
    end

    if (match = where_clause.match(/`pull_requests`.`id` IN \((.+)\)/)) ||
        (match = where_clause.match(/`pull_requests`.`id` = (\d+)/)) ||
        (match = where_clause.match(/`pull_request_id` IN \((.+)\)/)) ||
        (match = where_clause.match(/`pull_request_id` = (\d+)/))
      pr_ids = match[1].split(",").map(&:to_i)
      org_ids_for_query.concat(PullRequest.where(id: pr_ids).includes(:repository).map { |pr| pr.repository&.owner_id })
    end

    if (match = where_clause.match(/`issues`.`id` IN \((.+)\)/)) ||
        (match = where_clause.match(/`issues`.`id` = (\d+)/)) ||
        (match = where_clause.match(/`issue_id` IN \((.+)\)/)) ||
        (match = where_clause.match(/`issue_id` = (\d+)/))
      issue_ids = match[1].split(",").map(&:to_i)
      org_ids_for_query.concat(Issue.where(id: issue_ids).includes(:repository).map { |issue| issue.repository&.owner_id })
    end

    if (table_str.include?("`pinned_issues`") && match = where_clause.match(/`pinned_issues`.`id` = (\d+)/)) ||
        (table_str.include?("`pinned_issues`") && match = where_clause.match(/`pinned_issues`.`id` IN \((.+)\)/))
      pinned_issue_ids = match[1].split(",").map(&:to_i)
      org_ids_for_query.concat(PinnedIssue.where(id: pinned_issue_ids).includes(:repository).map { |pinned_issue| pinned_issue.repository&.owner_id })
      org_ids_for_query.concat(PinnedIssue.where(id: pinned_issue_ids).includes(issue: :repository).map { |pinned_issue| pinned_issue.issue&.repository&.owner_id })
    end

    if table_str.include?("`copilot_seat_assignments`") && match = where_clause.match(/`copilot_seat_assignments`.`id` = (\d+)/)
      seat_assignment_id = match[1].to_i
      org_ids_for_query.concat(Copilot::SeatAssignment.where(id: seat_assignment_id).map(&:organization_id))
    end

    if match = where_clause.match(/`labels`.`id` IN \((.+)\)/) ||
        (match = where_clause.match(/`labels`.`id` = (\d+)/)) ||
        (match = where_clause.match(/`label_id` IN \((.+)\)/)) ||
        (match = where_clause.match(/`label_id` = (\d+)/))
      label_ids = match[1].split(",").map(&:to_i)
      org_ids_for_query.concat(Label.where(id: label_ids).includes(:repository).map { |label| label.repository&.owner_id })
    end

    if (match = where_clause.match(/`pull_request_review_id` IN \((.+)\)/)) ||
        (match = where_clause.match(/`pull_request_review_id` = (\d+)/)) ||
        (match = where_clause.match(/`pull_request_reviews`.`id` IN \((.+)\)/)) ||
        (match = where_clause.match(/`pull_request_reviews`.`id` = (\d+)/))
      pr_review_ids = match[1].split(",").map(&:to_i)
      org_ids_for_query.concat(PullRequestReview.where(id: pr_review_ids).includes(pull_request: :repository).map { |prr| prr.pull_request&.repository&.owner_id })
    end

    if (match = where_clause.match(/`pull_request_review_comments`.`id` IN \((.+)\)/)) ||
        (match = where_clause.match(/`pull_request_review_comments`.`id` = (\d+)/))
      pr_review_comment_ids = match[1].split(",").map(&:to_i)
      preloaded_prr = PullRequestReviewComment.where(id: pr_review_comment_ids).includes(
        { pull_request: :repository },
        { pull_request_review: { pull_request: :repository } },
        { pull_request_review_thread: [{ pull_request: :repository }, { pull_request_review: { pull_request: :repository } }]
      })
      org_ids_for_query.concat(preloaded_prr.map { |prrc| prrc.pull_request&.repository&.owner_id })
      org_ids_for_query.concat(preloaded_prr.map { |prrc| prrc.pull_request_review&.pull_request&.repository&.owner_id })
      org_ids_for_query.concat(preloaded_prr.map { |prrc| prrc.pull_request_review_thread&.pull_request&.repository&.owner_id })
      org_ids_for_query.concat(preloaded_prr.map { |prrc| prrc.pull_request_review_thread&.pull_request_review&.pull_request&.repository&.owner_id })
    end

    if (match = where_clause.match(/`merge_queue_entries`.`id` IN \((.+)\)/)) ||
        (match = where_clause.match(/`merge_queue_entries`.`id` = (\d+)/))
      merge_queue_entry_ids = match[1].split(",").map(&:to_i)
      preloaded_mqe = MergeQueueEntry.where(id: merge_queue_entry_ids).includes(pull_request: :repository, queue: :repository)
      org_ids_for_query.concat(preloaded_mqe.map { |mqe| mqe.pull_request&.repository&.owner_id })
      org_ids_for_query.concat(preloaded_mqe.map { |mqe| mqe.queue&.repository&.owner_id })
    end

    if match = where_clause.match(/`merge_queues`.`id` IN \((.+)\)/) ||
        (match = where_clause.match(/`merge_queues`.`id` = (\d+)/)) ||
        (match = where_clause.match(/`merge_queue_id` IN \((.+)\)/)) ||
        (match = where_clause.match(/`merge_queue_id` = (\d+)/))
      merge_queue_ids = match[1].split(",").map(&:to_i)
      preloaded_mq = MergeQueue.where(id: merge_queue_ids).includes(:repository)
      org_ids_for_query.concat(preloaded_mq.map { |mq| mq.repository&.owner_id })
    end

    org_ids_for_query.uniq.compact
  end

  def relevant_tables
    @relevant_tables ||= JSON.parse(File.read(Rails.root.join("config", "data_partitioning", "tables_belongs_to_orgs.json"))).values.flatten
  end

  def record_maybe_cross_org_query(redacted_query, org_ids_for_query)
    message = {
      request_id: @request_id,
      redacted_sql: redacted_query[:redacted_sql],
      digest_sql: redacted_query[:digested_sql],
      transaction_uuid: redacted_query[:transaction_uuid],
      on_primary: redacted_query[:on_primary],
      connection_class_name: redacted_query[:connection_class_name],
      connection_class_role: redacted_query[:connection_class_role],
      is_cross_org: MAYBE_CROSS_ORG,
      discoverable_org_ids: org_ids_for_query.compact.uniq.sort,
    }

    Hydro::PublishRetrier.publish(
      message,
      schema: "github.database.v0.TrackedQuery",
      partition_key: @from
    )
  end

  def record_no_cross_org_queries_for_query(redacted_query)
    GitHub.logger.info("No cross org queries", {
      "code.namespace": "SocialExperienceInstrumentationJob",
      "code.function": "publish_query",
      "gh.request_id": @request_id,
      "gh.controller": @controller,
      "gh.action": @controller_action,
      "gh.method": @request_method,
      "gh.from": @from,
      "gh.catalog_service": @catalog_service,
      "gh.request_category": @request_category,
      "db.query.redacted_sql": redacted_query[:redacted_sql],
      "db.query.digested_sql": redacted_query[:digested_sql],
      "code.transaction_uuid": redacted_query[:transaction_uuid],
      "code.connection_class_name": redacted_query[:connection_class_name],
      "code.connection_class_role": redacted_query[:connection_class_role]
    })
  end

  def record_no_cross_org_queries_for_request
    message = {
      request_id: @request_id,
      is_cross_org: NOT_CROSS_ORG,
      discoverable_org_ids: [],
    }

    Hydro::PublishRetrier.publish(
      message,
      schema: "github.database.v0.TrackedQuery",
      partition_key: @from
    )
  end

  def guess_org_ids_from_insert_query(table_name, columns, rows)
    if columns.include?("organization_id")
      index = columns.index("organization_id")
      rows.map { |values| values[index] }.flatten.map(&:to_i).uniq
    elsif table_name == "repositories" && columns.include?("owner_id")
      index = columns.index("owner_id")
      rows.map { |values| values[index] }.flatten.map(&:to_i).uniq
    else
      []
    end
  end
end
