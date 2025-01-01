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
      content_exclusion_available? || coding_guidelines_available? || copilot_swe_agent_settings_enabled?
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

      if coding_guidelines_available?
        sections << {
          display_name: "Code review",
          preview_label: user_feature_enabled?(:copilot_code_review_ga) ? false : true,
          path: repo_repo_settings_copilot_code_review_path(user_id: @repository.owner_display_login, repository: @repository.name),
          item_id: :repo_settings_copilot_coding_guidelines
        }
      end

      if copilot_swe_agent_settings_enabled?
        sections << {
          display_name: "Coding agent",
          preview_label: true,
          path: repo_repo_settings_copilot_swe_agent_path(@repository.owner_display_login, @repository.name),
          item_id: :repo_settings_copilot_swe_agent
        }
      end
      sections
    end

    memoize def content_exclusion_available?
      ::Copilot::ContentExclusion.is_available?(@repository)
    end

    memoize def coding_guidelines_available?
      ::Copilot::User.new(current_user).copilot_coding_guidelines_enabled?(@repository)
    end

    memoize def copilot_swe_agent_settings_enabled?
      @repository.owner.copilot_swe_agent_enabled_for?(@repository)
    end
  end
end
