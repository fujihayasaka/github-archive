# typed: strict
# frozen_string_literal: true

module CopilotIssues
  class BulkCreateController < ApplicationController
    include ApplicationController::VerifiedFetchDependency

    CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
      "#{self}#create"
    ].freeze, T::Array[String])

    allow_verified_fetch only: [:create]

    before_action :dotcom_required
    before_action :feature_required

    class IssueMetadata < T::Struct
      const :title, String
      const :tag, String
      const :repository_id, Integer
      const :body, T.nilable(String)
      const :parent_tag, T.nilable(String)
      const :labels, T::Array[String]
      const :assignees, T::Array[String]
      const :milestone, T.nilable(Integer)
      const :issue_type, T.nilable(String)
      const :template, T.nilable(String)

      sig { returns(T::Hash[String, T.untyped]) }
      def serialize
        super.with_indifferent_access
      end
    end

    sig { void }
    def create
      issue_metadata_payloads = T.let([], T::Array[IssueMetadata])
      issues_map = T.let({}, T::Hash[String, IssueMetadata])
      return render_validation_error("No issues provided") if data.empty? || issues.empty?

      issues.each do |issue_metadata|
        metadata = issue_metadata.with_indifferent_access
        metadata_validation_error = validate_metadata(metadata)
        return render_validation_error(metadata_validation_error) if metadata_validation_error

        issue_metadata_payloads << IssueMetadata.new(
          title: metadata[:title],
          body: metadata[:body],
          tag: metadata[:tag],
          parent_tag: metadata[:parent_tag],
          repository_id: metadata[:repository_id].to_i,
          labels: metadata[:labels] || [],
          assignees: metadata[:assignees] || [],
          milestone: metadata[:milestone].to_i,
          issue_type: metadata[:issue_type],
          template: metadata[:template]
        )
      end

      repo_ids_to_issues = issue_metadata_payloads.group_by { |issue| issue.repository_id }
      repo_validation_error = validate_repositories(repo_ids_to_issues)
      return render_validation_error(repo_validation_error) if repo_validation_error

      bulk_create_id = create_token(parent_tag: T.must(issue_metadata_payloads.first).tag)
      status = BulkCreateJobStatus.find(bulk_create_id)
      if status.blank? || status.error?
        status = BulkCreateJobStatus.create(id: bulk_create_id)

        # TODO - Implement the job to handle bulk creation of issues
        # job = BulkCreateJob.perform_later(bulk_create_id, current_user, issue_metadata_payloads)
        # unless job
        #   raise RuntimeError.new("Failed to create export job")
        # end

        # status.queued!
      end

      body = {
        jobStatusUrl: job_status_path(status.id),
        jobId: status.id,
      }

      render json: body, status: 202
      # TODO - rescue job errors
    end

    private

    sig { void }
    def feature_required
      render_404 unless FeatureFlag.vexi.enabled?(:copilot_immersive_draft_issue_tree, current_user, default: false)
    end

    sig { params(error_message: String).void }
    def render_validation_error(error_message)
      GitHub.dogstats.increment("copilot_issues.bulk_create.error")
      GitHub.logger.warn(
        "Bulk create issues validation error", {
          "gh.request_id": GitHub.context[:request_id],
          "gh.request.action": GitHub.context[:controller_action],
          "gh.request.controller": GitHub.context[:controller],
          "gh.user.id": current_user.id,
          "gh.error.message": error_message,
        }
      )
      render json: { error: error_message }, status: :bad_request
    end

    sig { params(metadata: T::Hash[Symbol, T.untyped]).returns(T.nilable(String)) }
    def validate_metadata(metadata)
      return "Missing title" if metadata[:title].blank?
      return "Missing tag" if metadata[:tag].blank?
      "Missing repository_id" if metadata[:repository_id].blank?
    end

    sig { params(repo_ids_to_issues: T::Hash[Integer, T::Array[IssueMetadata]]).returns(T.nilable(String)) }
    def validate_repositories(repo_ids_to_issues)
      repository_ids = repo_ids_to_issues.keys
      repos = Repository.where(id: repository_ids)
      repos_delta = repository_ids - repos.pluck(:id)
      return "Invalid repository IDs: #{repos_delta.join(', ')}" if !repos_delta.empty?

      repos.each do |repo|
        return "Issues not enabled in repository #{repo.id}" if !repo.has_issues?
        return "No permission to create issues in repository #{repo.id}" if !repo.readable_by?(current_user)
      end

      nil
    end

    sig { params(parent_tag: String).returns(String) }
    def create_token(parent_tag:)
      Digest::SHA256.hexdigest([
        SecureRandom.uuid,
        current_user.id,
        parent_tag,
      ].join("/"))
    end

    sig { returns(T::Hash[String, T.untyped]) }
    memoize def data
      return {} if params[:data].nil?
      JSON.parse(params[:data]) || {}
    end

    sig { returns(T::Array[T::Hash[String, T.untyped]]) }
    memoize def issues
      data["issues"] || []
    end

    sig { returns(T.any(Symbol, User)) }
    def target_for_conditional_access
      return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      current_user
    end

    depends_on_clusters \
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Ballast,
      only: [:create]
  end
end
