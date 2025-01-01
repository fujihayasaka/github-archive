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
      content_exclusion_available? || coding_guidelines_available?
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
          preview_label: true,
          path: copilot_code_guidelines_path(user_id: @repository.owner_display_login, repository: @repository.name),
          item_id: :repo_settings_copilot_coding_guidelines
        }
      end

      sections
    end

    memoize def content_exclusion_available?
      ::Copilot::ContentExclusion.is_available?(@repository)
    end

    memoize def coding_guidelines_available?
      user_or_global_feature_enabled?(:copilot_coding_guidelines) &&
        @repository.owner.organization? &&
        @repository.adminable_by?(current_user) &&
        ::Copilot::Organization.new(@repository.owner).can_use_copilot_enterprise_features?
    end
  end
end
