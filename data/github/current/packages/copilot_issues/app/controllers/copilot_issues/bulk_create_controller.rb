# typed: strict
# frozen_string_literal: true

module CopilotIssues
  class BulkCreateController < ApplicationController
    include ApplicationController::JsonDependency
    include ApplicationController::VerifiedFetchDependency
    include CopilotIssues::Metrics
    include GitHub::RateLimitedRequest

    CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
      "#{self}#create"
    ].freeze, T::Array[String])

    # The number of _requests_ allowed per user per hour
    # _Not_ the maximum number of issues that can be requested/created.
    DEFAULT_MAX_REQUESTS = 20

    before_action :parse_json_params, only: [:create]
    allow_verified_fetch only: [:create]

    before_action :dotcom_required
    around_action :record_metrics, only: [:create]

    rate_limit_requests \
      only: [:create],
      max: DEFAULT_MAX_REQUESTS,
      ttl: 1.hour,
      key: :bulk_create_rate_limit_key,
      at_limit: :bulk_create_rate_limit_at_limit

    class BulkCreateError < T::Struct
      const :issue_tag, T.nilable(String)
      const :message, String
    end

    sig { void }
    def create
      return render_error("No issues provided") if data.empty? || issues.empty?
      return render_error("Number of issues exceeds the maximum limit of #{BulkCreateJobStatus::MAX_ISSUE_WRITES}.") if issues.size > BulkCreateJobStatus::MAX_ISSUE_WRITES

      repository_nwos = issues.map { |issue| issue["repository_nwo"] }.compact.uniq
      found_repositories = T.let(
        repository_nwos
          .map do |nwo|
            Repositories.domain.by_qualified_name(nwo)
          end
          .compact
          .index_by(&:name_with_display_owner),
        T::Hash[String, Repository]
      )
      validated_repo_ids = T.let(Set.new, T::Set[Integer])
      # Group parent issues
      parent_tags = Set.new(issues.map { |i| i["parent_tag"] }.uniq.compact)

      issues.each do |issue_metadata|
        metadata = issue_metadata.with_indifferent_access
        metadata_validation_error = validate_metadata(metadata)
        return render_error(metadata_validation_error) if metadata_validation_error

        repository_nwo = metadata[:repository_nwo]
        return render_error("Invalid repository", issue_tag: metadata[:tag]) if !found_repositories.keys.include?(repository_nwo)
        repo = T.must(found_repositories[repository_nwo])

        # Validate existing issue
        if metadata[:number].present?
          existing_issue = Issues.domain.by_number(Integer(metadata[:number]), repo_id: repo.id)
          existing_issue = T.cast(existing_issue, T.nilable(Issue))
          return render_error("Existing issue not found", issue_tag: metadata[:tag]) if existing_issue.nil?
          return render_error("Existing issue is a pull request", issue_tag: metadata[:tag]) if existing_issue.pull_request?
        end

        # Validate if user can create issues based on repo permissions
        if !validated_repo_ids.include?(repo.id)
          repo_validation_error = validate_repository(repo)
          return render_error(repo_validation_error, issue_tag: metadata[:tag]) if repo_validation_error

          # If the issue has subissues, validate if user can create subissues based on repo permissions
          if parent_tags.include?(metadata[:tag])
            subissues_permissions_error = validate_subissues_permissions(repo)
            return render_error(subissues_permissions_error, issue_tag: metadata[:tag]) if subissues_permissions_error
          end

          validated_repo_ids << repo.id
        end
        # Add the repository_id so the job can act on already-validated IDs
        issue_metadata["repository_id"] = repo.id
      end

      root_tag = get_root_issue_tag(issues.map(&:with_indifferent_access))
      return render_error("No root issue found") if root_tag.nil?

      bulk_create_id = create_token(parent_tag: root_tag)
      status = BulkCreateJobStatus.find(bulk_create_id)
      new_job_created = T.let(false, T::Boolean)

      if status.blank? || status.error?
        status = BulkCreateJobStatus.create(id: bulk_create_id)

        job = BulkIssueCreationJob.perform_later(
          bulk_create_id:,
          issue_metadata_payloads: issues.map(&:with_indifferent_access),
          root_tag:,
          current_user:
        )
        unless job
          raise RuntimeError.new("Failed to enqueue job for bulk issue creation")
        end

        new_job_created = true
        status.queued!
      end

      body = {
        jobStatusUrl: job_status_path(status.id),
        jobId: status.id,
      }

      log_info(bulk_create_id, job_created: new_job_created)

      render json: body, status: 202
      # TODO - rescue job errors
    rescue => e # rubocop:todo Lint/RescueException
      render_error(e.message)
    end

    private

    sig { returns(String) }
    def bulk_create_rate_limit_key
      "copilot_issues:bulk_create:#{current_user.id}"
    end

    sig { void }
    def bulk_create_rate_limit_at_limit
      GitHub.dogstats.increment("copilot_issues.bulk_create.controller.at_limit")
      GitHub.logger.warn(
        "Bulk create issues rate limit reached", {
          "gh.request_id": GitHub.context[:request_id],
          "gh.request.action": GitHub.context[:controller_action],
          "gh.request.controller": GitHub.context[:controller],
          "gh.user.id": current_user.id,
          "gh.total_issues_requested": issues.length,
        }
      )

      render json: { error: "Rate limit exceeded. Please try again later." }, status: :too_many_requests
    end

    sig { params(block: T.proc.void).void }
    def record_metrics(&block)
      collect_metrics("copilot_issues.bulk_create.create") do
        yield
      end
    end

    sig { params(bulk_create_id: String, job_created: T::Boolean).void }
    def log_info(bulk_create_id, job_created: true)
      GitHub.dogstats.count("copilot_issues.bulk_create.job.total_issues_requested", issues.length)
      GitHub.logger.info(
        "Bulk create issues validation completed successfully",
        {
          "gh.request_id": GitHub.context[:request_id],
          "gh.request.controller": GitHub.context[:controller],
          "gh.user.id": current_user.id,
          "gh.bulk_create_id": bulk_create_id,
          "gh.total_issues_requested": issues.length,
        }
      )
    end

    sig { params(error_message: String, issue_tag: T.nilable(String)).void }
    def render_error(error_message, issue_tag: nil)
      total_issues_requested = issues.length
      GitHub.dogstats.increment("copilot_issues.bulk_create.controller.error")
      GitHub.logger.warn(
        "Bulk create issues validation error", {
          "gh.request_id": GitHub.context[:request_id],
          "gh.request.action": GitHub.context[:controller_action],
          "gh.request.controller": GitHub.context[:controller],
          "gh.user.id": current_user.id,
          "gh.error.message": error_message,
          "gh.total_issues_requested": total_issues_requested,
        }
      )
      error = BulkCreateError.new(
        issue_tag:,
        message: error_message
      )
      render json: { error: error }, status: :bad_request
    end

    sig { params(metadata: T::Hash[Symbol, T.untyped]).returns(T.nilable(String)) }
    def validate_metadata(metadata)
      return "Missing tag" if metadata[:tag].blank?
      return "Missing repository_nwo" if metadata[:repository_nwo].blank?

      has_title = metadata[:title].is_a?(String) && !metadata[:title].empty?
      has_number = metadata[:number].is_a?(Integer) && metadata[:number] > 0
      return "Missing existing issue number or draft issue title" if has_title == has_number

      nil
    end

    sig { params(repository: Repository).returns(T.nilable(String)) }
    def validate_repository(repository)
      return "User is not authorized to access repository #{repository.name_with_display_owner}" if unauthorized_org?(repository)
      return "No permission to create issues in repository #{repository.name_with_display_owner}" if !repository.readable_by?(current_user)
      return "Repository #{repository.name_with_display_owner} is archived" if repository.archived?
      return "Issues not enabled in repository #{repository.name_with_display_owner}" if !repository.has_issues?
      return "Interactions on repository #{repository.name_with_display_owner} have been restricted" if interaction_limits_enabled?(repository)

      nil
    end

    sig { params(repository: Repository).returns(T.nilable(String)) }
    def validate_subissues_permissions(repository)
      # User needs a minimum of triage permissions to create subissues
      return "No permission to create subissues in repository #{repository.name_with_display_owner}" if !Issue::PermissionsDependency::repo_triageable_by?(current_user, repository)
      nil
    end

    sig { params(repository: Repository).returns(T::Boolean) }
    def interaction_limits_enabled?(repository)
      interaction_ability = RepositoryInteractionAbility.new(repository)
      active_limit = interaction_ability.overall_active_limit
      return false if active_limit == :no_limit
      return false if RepositoryInteractionAbility.user_exempt?(active_limit, repository, current_user)

      true
    end

    sig { returns(T::Array[Integer]) }
    memoize def unauthorized_org_ids
      cap_filter.unauthorized_resource_ids(current_user&.organizations)
    end

    sig { params(repository: Repository).returns(T::Boolean) }
    def unauthorized_org?(repository)
      return false if !repository.owner.is_a?(Organization)
      unauthorized_org_ids.include?(repository.owner_id)
    end

    sig { params(issues: T::Array[T::Hash[Symbol, T.untyped]]).returns(T.nilable(String)) }
    def get_root_issue_tag(issues)
      root_issue = issues.find { |issue| issue[:parent_tag].nil? }
      return nil if root_issue.nil?
      root_issue[:tag]
    end

    sig { params(parent_tag: String).returns(String) }
    def create_token(parent_tag:)
      Digest::SHA256.hexdigest([
        "8c1121db-830b-4c04-9d4b-7d29c933377d", # set a fixed random number to prevent creating a different id from the same parent
        current_user.id,
        parent_tag,
      ].join("/"))
    end

    sig { returns(T::Hash[String, T.untyped]) }
    memoize def data
      return {} if params[:data].nil?
      params[:data].as_json
    end

    sig { returns(T::Array[T::Hash[String, T.untyped]]) }
    memoize def issues
      (data["issues"] || []).filter { |i| i.present? }
    end

    sig { returns(T.any(Symbol, User)) }
    def target_for_conditional_access
      return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      current_user
    end

    depends_on_clusters \
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::Copilot,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      only: [:create]

    depends_on_clusters \
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      only: [:create],
      optional: true
  end
end
