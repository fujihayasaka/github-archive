# typed: true
# frozen_string_literal: true

module Settings
  class CopilotRepoNavComponent < ApplicationComponent
    include ApplicationComponent::Rescuable

    rescue_from ActiveRecord::ActiveRecordError, with: :nothing

    def initialize(entity:, **system_arguments)
      @repository = entity
      @system_arguments = system_arguments
    end

    private

    def render?
      return false if GitHub.enterprise?

      content_exclusion_available? || code_review_section_enabled? || copilot_swe_agent_settings_enabled? || copilot_memory_enabled?
    end

    def sub_sections
      sections = []

      if content_exclusion_available?
        sections << {
          display_name: "Content exclusion",
          path: repo_repo_settings_copilot_content_exclusion_path(@repository.owner, @repository),
          item_id: :repo_settings_copilot_content_exclusion
        }
      end

      if code_review_section_enabled?
        sections << {
          display_name: "Code review",
          path: repo_repo_settings_copilot_code_review_path(user_id: @repository.owner_display_login, repository: @repository.name),
          item_id: :repo_settings_copilot_coding_guidelines
        }
      end

      if copilot_swe_agent_settings_enabled?
        sections << {
          display_name: "Cloud agent",
          path: repo_repo_settings_copilot_swe_agent_path(@repository.owner_display_login, @repository.name),
          item_id: :repo_settings_copilot_swe_agent
        }
      end

      if mcp_settings_enabled?
        sections << {
          display_name: "MCP servers",
          path: repo_repo_settings_copilot_mcp_path(@repository.owner_display_login, @repository.name),
          item_id: :repo_settings_copilot_mcp
        }
      end

      if copilot_memory_enabled?
        sections << {
          display_name: "Memory",
          path: repo_repo_settings_copilot_memory_path(@repository.owner_display_login, @repository.name),
          item_id: :repo_settings_copilot_memory,
          preview_label: true
        }
      end

      sections
    end

    memoize def content_exclusion_available?
      ::Copilot::ContentExclusion.is_available?(@repository)
    end

    memoize def copilot_swe_agent_settings_enabled?
      @repository.owner.copilot_swe_agent_enabled_for?(@repository)
    end

    memoize def mcp_settings_enabled?
      (FeatureFlag.vexi.enabled?("ccr_mcp_repo_settings", [@repository, @repository.owner], default: false) ||
        @repository.feature_enabled_for_repo_or_owner?("copilot-code-reviews-enable-mcp-proxy") ||
        preview_mcp_skills_enabled?) &&
        (copilot_swe_agent_settings_enabled? || code_review_section_enabled?)
    end

    memoize def preview_mcp_skills_enabled?
      return false unless FeatureFlag.vexi.enabled?("ccr-enable-preview-mcp-skills", [@repository, @repository.owner], default: false)

      if @repository.in_organization?
        org = @repository.organization
        return false unless org

        copilot_org = ::Copilot::Organization.new(org)
        copilot_org.code_review_beta_features_enabled?
      else
        copilot_user = current_copilot_user_v2
        return false unless copilot_user

        copilot_user.code_review_beta_features_enabled?
      end
    end

    memoize def code_review_section_enabled?
      if @repository.in_organization?
        org = @repository.organization
        return false unless org

        copilot_org = ::Copilot::Organization.new(org)
        ::Copilot::Policies::CodeReview.enabled?(copilot_org)
      else
        copilot_user = current_copilot_user_v2
        return false unless copilot_user

        copilot_user.code_review_enabled?
      end
    end

    memoize def copilot_memory_enabled?
      if FeatureFlag.vexi.enabled?("copilot_memory_enablement_policy", current_user, default: false)
        ::Copilot::Policies::Memory.effective_value(T.must(current_copilot_user)) == "enabled"
      else
        false
      end
    end
  end
end
