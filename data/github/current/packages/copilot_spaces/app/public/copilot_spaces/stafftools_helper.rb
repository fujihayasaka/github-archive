# typed: strict
# frozen_string_literal: true

module CopilotSpaces
  class StafftoolsHelper
    # Check if user is blocked specifically from Copilot Spaces
    sig { params(user: User).returns(T::Boolean) }
    def self.user_blocked_from_spaces?(user)
      FeatureFlag.vexi.enabled?(:copilot_spaces_user_blocked, user, default: false)
    end

    # Block user from Copilot Spaces using feature flag
    sig { params(user: User, actor: User, reason: String).void }
    def self.block_user_from_spaces!(user, actor, reason)
      # Enable the blocking feature flag for this user
      FeatureFlag.vexi_management.add_feature_flag_actors(:copilot_spaces_user_blocked, [user]) # rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage

      # Log the action
      GitHub.logger.info(
        "Copilot Spaces user blocked via feature flag",
        "gh.copilot_spaces.user_block.action" => "block",
        "gh.copilot_spaces.user_block.reason" => reason,
        "gh.user.login" => user.display_login,
        "gh.actor.login" => actor.display_login
      )
    end

    # Unblock user from Copilot Spaces using feature flag
    sig { params(user: User, actor: User, reason: String).void }
    def self.unblock_user_from_spaces!(user, actor, reason)
      # Disable the blocking feature flag for this user
      FeatureFlag.vexi_management.remove_feature_flag_actors(:copilot_spaces_user_blocked, [user]) # rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage

      # Log the action
      GitHub.logger.info(
        "Copilot Spaces user unblocked via feature flag",
        "gh.copilot_spaces.user_block.action" => "unblock",
        "gh.copilot_spaces.user_block.reason" => reason,
        "gh.user.login" => user.display_login,
        "gh.actor.login" => actor.display_login
      )
    end

    # Helper methods for resource handling
    sig { params(resource: T.untyped).returns(String) }
    def self.resource_title(resource)
      case resource.resource_type
      when "github_file"
        resource.metadata["file_path"] || "Unknown file"
      when "repository"
        if resource.parsed_metadata.repository
          resource.parsed_metadata.repository.name_with_display_owner
        else
          "Unknown repository"
        end
      when "github_issue"
        if resource.metadata["number"]
          "##{resource.metadata['number']}"
        else
          "GitHub Issue"
        end
      when "github_pull_request"
        if resource.metadata["number"]
          "##{resource.metadata['number']}"
        else
          "GitHub Pull Request"
        end
      when "free_text"
        resource.metadata["name"] || "Free text"
      when "uploaded_text_file"
        resource.metadata["name"] || "Uploaded file"
      when "media_content"
        resource.metadata["name"] || "Media content"
      else
        "Resource"
      end
    end

    sig { params(resource: T.untyped).returns(String) }
    def self.resource_details(resource)
      case resource.resource_type
      when "github_file"
        repo = get_repository_for_resource(resource)
        repo_name = repo&.name_with_display_owner || "Unknown repository"
        "#{repo_name}"
      when "repository"
        repo = resource.parsed_metadata.repository
        repo&.description&.truncate(100) || "No description"
      when "github_issue", "github_pull_request"
        repo = get_repository_for_resource(resource)
        repo_name = repo&.name_with_display_owner || "Unknown repository"
        "in #{repo_name}"
      when "free_text"
        text = resource.metadata["text"] || ""
        text.truncate(100)
      when "uploaded_text_file"
        "Uploaded file"
      when "media_content"
        "Media content"
      else
        "Type: #{resource.resource_type}"
      end
    end

    sig { params(resource: T.untyped).returns(T::Boolean) }
    def self.resource_viewable?(resource)
      case resource.resource_type
      when "github_file", "github_issue", "github_pull_request"
        get_repository_for_resource(resource).present?
      when "repository"
        resource.parsed_metadata.repository.present?
      else
        false
      end
    end

    sig { params(resource: T.untyped, request_base_url: String).returns(T.nilable(String)) }
    def self.resource_url(resource, request_base_url)
      case resource.resource_type
      when "github_file"
        repo = get_repository_for_resource(resource)
        return nil unless repo && resource.metadata["file_path"]
        # Construct the file URL
        sha = resource.metadata["sha"] || repo.default_branch
        "#{request_base_url}/#{repo.name_with_display_owner}/blob/#{sha}/#{resource.metadata['file_path']}"
      when "repository"
        repo = resource.parsed_metadata.repository
        return nil unless repo
        "#{request_base_url}/#{repo.name_with_display_owner}"
      when "github_issue"
        repo = get_repository_for_resource(resource)
        return nil unless repo && resource.metadata["number"]
        "#{request_base_url}/#{repo.name_with_display_owner}/issues/#{resource.metadata['number']}"
      when "github_pull_request"
        repo = get_repository_for_resource(resource)
        return nil unless repo && resource.metadata["number"]
        "#{request_base_url}/#{repo.name_with_display_owner}/pull/#{resource.metadata['number']}"
      else
        nil
      end
    end

    # Helper to get repository from metadata
    # Note: This doesn't use caching across instances, which is fine for stafftools usage
    sig { params(resource: T.untyped).returns(T.nilable(Repository)) }
    def self.get_repository_for_resource(resource)
      return nil unless resource.repository_id

      begin
        Repositories::Public.find_active(resource.repository_id)
      rescue ActiveRecord::RecordNotFound
        nil
      end
    end
  end
end
