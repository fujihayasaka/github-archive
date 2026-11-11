# typed: true
# frozen_string_literal: true

module CopilotChat
  # Resolves resources by type and identifier for access control checks.
  #
  # This class handles resource lookup logic for authorization decisions in Copilot APIs.
  # It supports multiple lookup strategies including:
  # - Direct resource lookup by type and ID
  # - Repository lookup by NWO (name with owner)
  # - Issue/PR lookup by number and repository NWO
  # - Fallback handling for deleted/transferred issues
  # - Fallback handling for deleted/transferred discussions
  #
  # @return [ActiveRecord::Base, nil] The resolved resource or nil if not found
  class ControlAccessHelper
    sig do
      params(
        resource: T.untyped,
        repository_nwo: T.untyped,
        repository_id: Integer,
        organization_id: T.untyped
      ).returns(T.untyped)
    end
    def self.extra_opts(resource, repository_nwo, repository_id, organization_id)
      # Need to set this up for the access control call, it expects these to be explicitly nil
      extra_opts = {
        current_repo: T.let(nil, T.nilable(Repository)),
        current_org: T.let(nil, T.nilable(Organization)),
      }

      if resource.is_a?(Repository)
        return nil if resource.owner.nil?
        extra_opts[:current_repo] = resource
        extra_opts[:current_org] = T.cast(resource.owner, Organization) if resource.owner&.organization?
        extra_opts[:organization_id] = resource.owner_id if resource.owner&.organization?
      end

      # Check if the resource has a repository nwo attribute passed
      if repository_nwo.present? && repository_id == 0
        if FeatureFlag.vexi.enabled?(:copilot_chat_search_renamed_repos, default: false)
          repo = Repository.with_name_with_owner(repository_nwo, search_redirects: true)
        else
          repo = Repository.with_name_with_owner(repository_nwo)
        end

        return nil unless repo
        extra_opts[:repo] = repo
        extra_opts[:current_repo] = repo
        extra_opts[:current_org] = T.cast(repo.owner, Organization) if repo.owner&.organization?
        extra_opts[:organization_id] = repo.owner_id if repo.owner&.organization?
      end

      # Include the repository if passed
      if repository_id > 0
        repo = T.cast(::Repositories.domain.by_id(repository_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
        return nil unless repo
        extra_opts[:repo] = repo
        extra_opts[:current_repo] = repo
        extra_opts[:current_org] = T.cast(repo.owner, Organization) if repo.owner&.organization?
        extra_opts[:organization_id] = repo.owner_id if repo.owner&.organization?
      end

      # Include the organization if passed
      if organization_id > 0
        org = Organization.find_by(id: organization_id)
        return nil unless org
        extra_opts[:organization] = org
        extra_opts[:current_org] = org
      end

      # If resource has a repository attribute, include it in request
      if !extra_opts[:repo].present? && resource.respond_to?(:repository)
        repo = resource.repository
        return nil unless repo
        extra_opts[:repo] = repo
        extra_opts[:current_repo] = repo
        extra_opts[:current_org] = T.cast(repo.owner, Organization) if repo.owner&.organization?
        extra_opts[:organization_id] = repo.owner_id if repo.owner&.organization?
      end

      # Ensure organization_id is always set (0 for user-owned repos, org ID for org-owned repos)
      extra_opts[:organization_id] ||= extra_opts[:current_org]&.id || 0

      extra_opts
    end

    sig do
      params(
        resource_type: T.untyped,
        repository_nwo: T.untyped,
        repository_id: Integer,
        resource_id: T.untyped,
        user: T.untyped,
        logging_enabled: T::Boolean
      ).returns(T.untyped)
    end
    def self.resolve_resource(resource_type, repository_nwo, repository_id, resource_id, user: nil, logging_enabled: false)
      # Track if we did a repo fallback for auth
      repo_fallback = false

      # Look up the resource by type and ID
      if resource_type == "IssueNumber" || resource_type == "PullRequestNumber"
        if FeatureFlag.vexi.enabled?(:copilot_chat_search_renamed_repos, default: false)
          resource = Issue.find_by(repository: Repository.with_name_with_owner(repository_nwo, search_redirects: true), number: resource_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        else
          resource = Issue.find_by(repository: Repository.with_name_with_owner(repository_nwo), number: resource_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        end

        if resource && resource.pull_request?
          resource = resource.pull_request
        end

        # (1/2) Handle missing issues by checking deleted/transferred records or falling back to repo auth.
        # This fixes a bug where threads won't load if users thread includes transferred/deleted issues
        if resource_id && !resource
          # Check deleted/transferred issue records by repository and number
          if FeatureFlag.vexi.enabled?(:copilot_chat_search_renamed_repos, default: false)
            repo = Repository.with_name_with_owner(repository_nwo, search_redirects: true)
          else
            repo = Repository.with_name_with_owner(repository_nwo)
          end
          resource = find_deleted_or_transferred_issue_by_number(repo, resource_id)
          repo_fallback = resource.is_a?(Repository) if resource

          # Fall back to repo auth if no deleted/transferred record found
          if !resource
            repo_fallback = true
            resource = get_repo_resource_as_fallback(repository_nwo, repository_id, resource_id)
          end
        end

        owner_org_id = resource&.repository&.owner_id || 0
      else
        resource_type_class = resource_type.classify.constantize

        if resource_type_class == Repository
          if repository_nwo.present? && resource_id.zero? && repository_id.zero?
            if FeatureFlag.vexi.enabled?(:copilot_chat_search_renamed_repos, default: false)
              resource = Repository.with_name_with_owner(repository_nwo, search_redirects: true)
            else
              resource = Repository.with_name_with_owner(repository_nwo)
            end
          elsif FeatureFlag.vexi.enabled?(:repos_by_id_api_twirp, default: false)
            resource = ::Repositories.domain.by_id(resource_id)
          else
            resource = Repository.find_by(id: resource_id)
          end
        else
          resource = resource_type_class.find_by(id: resource_id)

          # (2/2) Handle missing issues by checking deleted/transferred records or falling back to repo auth.
          # This fixes a bug where threads won't load if users thread includes transferred/deleted issues
          if resource_id && !resource && resource_type == "Issue"
            # Check deleted/transferred issue records by ID
            resource = find_deleted_or_transferred_issue_by_id(resource_id)
            repo_fallback = resource.is_a?(Repository) if resource

            # Fall back to repo auth if no deleted/transferred record found
            if !resource
              repo_fallback = true
              resource = get_repo_resource_as_fallback(repository_nwo, repository_id, resource_id)
            end
          end

          # Handle missing discussions by checking deleted/transferred records or falling back to repo auth.
          # This fixes a bug where threads won't load if user's thread includes deleted/transferred discussions
          if resource_id && !resource && resource_type == "Discussion"
            if FeatureFlag.vexi.enabled?(:copilot_chat_discussion_fallback, user, default: false)
              resource = find_deleted_or_transferred_discussion_by_id(resource_id)
              repo_fallback = resource.is_a?(Repository) if resource

              if !resource
                repo_fallback = true
                resource = get_repo_resource_as_fallback(repository_nwo, repository_id, resource_id)
              end
            end
          end

          if !resource && logging_enabled
            GitHub.logger.warn("[ControlAccessDecision] Resource not found: type=#{resource_type}, resource_id=#{resource_id}, repo_nwo=#{repository_nwo}")
          end
        end
      end

      [resource, repo_fallback]
    end

    def self.get_repo_resource_as_fallback(repository_nwo, repository_id, resource_id)
      GitHub.logger.warn("[ControlAccessHelper] Issue not found, falling back to repo auth: resource_id=#{resource_id}, repo_nwo=#{repository_nwo}, repo_id=#{repository_id}")
      if repository_nwo.present?
        if FeatureFlag.vexi.enabled?(:copilot_chat_search_renamed_repos, default: false)
          resource = Repository.with_name_with_owner(repository_nwo, search_redirects: true)
        else
          resource = Repository.with_name_with_owner(repository_nwo)
        end
      elsif repository_id > 0
        resource = Repository.find_by(id: repository_id)
      end
      resource
    end

    # Attempts to find a transferred or deleted issue by its original ID.
    # Returns the new issue if transferred, or the repository if deleted.
    # Returns nil if no record is found.
    sig do
      params(
        resource_id: T.untyped
      ).returns(T.nilable(T.any(Issues::IIssue, Repository)))
    end
    def self.find_deleted_or_transferred_issue_by_id(resource_id)
      return nil unless resource_id

      # First check if the issue was transferred using domain method
      new_issue = ::Issues.domain.transferred_by_id(resource_id)
      if new_issue
        GitHub.logger.info("[ControlAccessHelper] Found transferred issue: original_id=#{resource_id}, new_id=#{new_issue.id}")
        return new_issue
      end

      # Then check if the issue was deleted using domain method
      deleted_metadata = ::Issues.domain.deleted_by_id(resource_id)
      if deleted_metadata
        repo = deleted_metadata[:repository]
        if repo
          GitHub.logger.info("[ControlAccessHelper] Found deleted issue: original_id=#{resource_id}, repo_id=#{repo.id}")
          return repo
        else
          GitHub.logger.warn("[ControlAccessHelper] Deleted issue found but repository is nil: original_id=#{resource_id}")
        end
      end

      nil
    end

    # Attempts to find a transferred or deleted issue by its repository and issue number.
    # Returns the new issue if transferred, or the repository if deleted.
    # Returns nil if no record is found.
    sig do
      params(
        repository: T.nilable(Repository),
        issue_number: T.untyped
      ).returns(T.nilable(T.any(Issues::IIssue, Repository)))
    end
    def self.find_deleted_or_transferred_issue_by_number(repository, issue_number)
      return nil unless repository && issue_number

      # First check if the issue was transferred using domain method
      new_issue = ::Issues.domain.transferred_by_number(repository, issue_number)
      if new_issue
        GitHub.logger.info("[ControlAccessHelper] Found transferred issue by number: repo=#{repository.name_with_display_owner}, number=#{issue_number}, new_id=#{new_issue.id}")
        return new_issue
      end

      # Then check if the issue was deleted using domain method
      deleted_metadata = ::Issues.domain.deleted_by_number(repository, issue_number)
      if deleted_metadata
        GitHub.logger.info("[ControlAccessHelper] Found deleted issue by number: repo=#{repository.name_with_display_owner}, number=#{issue_number}")
        return repository
      end

      nil
    end

    # Attempts to find a transferred or deleted discussion by its original ID.
    # Returns the new discussion if transferred, or the repository if deleted.
    # Returns nil if no record is found.
    sig do
      params(
        resource_id: T.untyped
      ).returns(T.nilable(T.any(Discussion, Repositories::IRepository)))
    end
    def self.find_deleted_or_transferred_discussion_by_id(resource_id)
      return nil unless resource_id

      # First check if the discussion was transferred
      new_discussion_id = DiscussionTransfer.find_new_id_by_original_id(original_id: resource_id)
      if new_discussion_id
        new_discussion = Discussion.find_by(id: new_discussion_id)
        if new_discussion
          GitHub.logger.info("[ControlAccessHelper] Found transferred discussion: original_id=#{resource_id}, new_id=#{new_discussion.id}")
          return new_discussion
        end
      end

      # Then check if the discussion was deleted
      deleted_discussion = DeletedDiscussion.find_by(old_discussion_id: resource_id)
      if deleted_discussion
        repo = deleted_discussion.repository
        if repo
          GitHub.logger.info("[ControlAccessHelper] Found deleted discussion: original_id=#{resource_id}, repo_id=#{repo.id}")
          return repo
        else
          GitHub.logger.warn("[ControlAccessHelper] Deleted discussion found but repository is nil: original_id=#{resource_id}")
        end
      end

      nil
    end
  end
end
