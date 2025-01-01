# typed: true
# frozen_string_literal: true

module CopilotIssues
  class BulkIssueCreationJob < ApplicationJob
    include GitHub::Memoizer
    include CopilotIssues::Metrics

    queue_as :copilot_issues_bulk_create

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    before_enqueue do |job|
      # Copilot chat does not run on GHES
      throw(:abort) if GitHub.enterprise?

      raise ArgumentError.new("BulkCreateJobStatus ID is required") if job.arguments.empty? || bulk_create_id.nil?
      raise ArgumentError.new("Issue metadata payloads are required") if issue_metadata_payloads.empty?
      raise ArgumentError.new("Root tag is required") if root_tag.nil? || root_tag.empty?
      raise ArgumentError.new("Current user is required") if current_user.nil?
      raise ArgumentError.new("Number of issues exceeds the maximum limit") if issue_metadata_payloads.size > BulkCreateJobStatus::MAX_ISSUE_WRITES
    end

    before_perform do |_job|
      job_status.started!
    end

    around_perform do |_, block|
      collect_metrics("copilot_issues.bulk_create.perform") do
        block.call
      end
    end

    sig do
      params(
        bulk_create_id: String,
        issue_metadata_payloads: T::Array[T::Hash[String, T.untyped]],
        root_tag: String,
        current_user: User,
      ).void
    end
    def perform(bulk_create_id:, issue_metadata_payloads:, root_tag:, current_user:)
      root_node = issues_payload.draft_issue_tree_map[root_tag]
      if root_node.nil?
        GitHub.dogstats.increment("copilot_issues.bulk_create.error", tags: all_stats_tags)
        raise RuntimeError.new("Root issue node not found in the tree map")
      end

      repository = root_node.item.repository
      create_bulk_issues_with_hierarchy(
        root_node,
        created_issues: [],
      )

      job_status.success!
      log_success
    rescue => e # rubocop:disable Lint/RescueException
      report_job_error(e)
    end

    private

    sig { params(errors: T::Array[String], repository_id: Integer, issue_tag: String).void }
    def report_continuable_errors(errors, repository_id, issue_tag)
      error_type = "project_assignment" # TODO: differentiate error types in the future
      GitHub.dogstats.increment("copilot_issues.bulk_create.job.error", tags: all_stats_tags + ["error:#{error_type}"])
      GitHub.logger.warn("Bulk create issues job: issues created with errors", {
        "gh.request_id": GitHub.context[:request_id],
        "gh.job.name": self.class.name,
        "gh.user.id": current_user.id,
        "gh.bulk_create_id": bulk_create_id,
        "gh.repository_id": repository_id,
        "gh.issue_tag": issue_tag,
        "gh.domain.errors": errors,
        "gh.error_type": error_type,
      })
    end

    sig { params(error: StandardError).void }
    def report_job_error(error)
      error_kwargs = if error.is_a?(BulkCreatePayload::IssueCreationError)
        {
          "gh.repository_id": error.repository_id,
          "gh.issue_tag": error.issue_tag,
          "gh.domain.errors": error.errors
        }
      else
        {}
      end

      GitHub.dogstats.increment("copilot_issues.bulk_create.job.error", tags: all_stats_tags + ["error:issue_creation"])
      GitHub.logger.warn(
        "Bulk create issues job: #{error.message}", {
        "gh.request_id": GitHub.context[:request_id],
        "gh.job.name": self.class.name,
        "gh.user.id": current_user.id,
        "gh.error.message": error.message,
        "gh.bulk_create_id": bulk_create_id,
        "gh.error_type": "issue_creation",
        **error_kwargs,
        }
      )
      job_status.error!(ttl: 7.days)
      raise error
    end

    sig { void }
    def log_success
      total_issues_created = job_status.completed_issues.length
      GitHub.dogstats.increment("copilot_issues.bulk_create.job.success", tags: all_stats_tags)
      GitHub.dogstats.count("copilot_issues.bulk_create.job.total_issues_created", total_issues_created, tags: all_stats_tags)

      GitHub.logger.info(
        "Bulk create issues job completed successfully",
        {
          "gh.request_id": GitHub.context[:request_id],
          "gh.job.name": self.class.name,
          "gh.user.id": current_user.id,
          "gh.bulk_create_id": bulk_create_id,
          "gh.total_issues_created": total_issues_created,
        }
      )
    end

    sig do
      params(
        current_node: BulkCreatePayload::IssueNode,
        created_issues: T::Array[BulkCreateJobStatus::IssueIdentifiers],
      ).void
    end
    def create_bulk_issues_with_hierarchy(current_node, created_issues: [])
      repository = current_node.item.repository
      issue_attributes = current_node.item
      resolved_issue = issues_payload.process_issue(issue_attributes, repository)

      issue_identifiers = BulkCreateJobStatus::IssueIdentifiers.new(
        tag: current_node.tag,
        id: T.must(resolved_issue.database_id),
        number: resolved_issue.number.to_i,
        href: T.must(resolved_issue.url),
        repository_id: repository.id,
        errors: issues_payload.errors,
      )

      created_issues << issue_identifiers

      # Update job status once projects are assigned as well
      job_status.add_completed_issues(issue_identifiers)
      job_status.set_percentage((created_issues.length / issue_metadata_payloads.length) * 100)

      if issues_payload.errors.any?
        report_continuable_errors(issues_payload.errors, repository.id, current_node.tag)
      end

      if current_node.children.any?
        parent_issue_id = resolved_issue.global_relay_id
        current_node.children.each do |child_node|
          child_node.item.parent_issue_id = parent_issue_id
          create_bulk_issues_with_hierarchy(child_node, created_issues:)
        end
      end
    end

    sig { returns(BulkCreatePayload) }
    memoize def issues_payload
      BulkCreatePayload.new(issue_metadata_payloads, current_user)
    end

    sig { returns(String) }
    memoize def root_tag
      self.arguments.dig(0, :root_tag)
    end

    sig { returns(User) }
    memoize def current_user
      self.arguments.dig(0, :current_user)
    end

    sig { returns(T::Array[T::Hash[String, T.untyped]]) }
    memoize def issue_metadata_payloads
      self.arguments.dig(0, :issue_metadata_payloads) || []
    end

    sig { returns(String) }
    memoize def bulk_create_id
      self.arguments.dig(0, :bulk_create_id)
    end

    sig { returns(BulkCreateJobStatus) }
    memoize def job_status
      status = CopilotIssues::BulkCreateJobStatus.find(bulk_create_id)
      if status.nil?
        GitHub.dogstats.increment("copilot_issues.bulk_create.job_status_not_found", tags: all_stats_tags)
        raise RuntimeError.new("BulkCreateJobStatus doesn't exist")
      end

      T.must(status)
    end
  end
end
