# typed: true
# frozen_string_literal: true

module Organizations::Settings::ThirdPartyAccess::PersonalAccessTokens::Filters
  class PermissionFilterListComponent < ApplicationComponent

    VALID_RESOURCE_PARENTS = [
      Repository, Organization
    ].freeze

    ACTIONS = %w[read write].freeze

    attr_reader :resource_parent, :programmatic_actor, :selected_permission

    def initialize(resource_parent:, selected_permission:, programmatic_actor:)
      @resource_parent = resource_parent
      @selected_permission = selected_permission
      @programmatic_actor = programmatic_actor
    end

    def render?
      VALID_RESOURCE_PARENTS.include?(resource_parent)
    end

    def actions
      ACTIONS
    end

    memoize def resources
      @resources =
        case resource_parent.name
        when "Repository"
          Repository::Resources.subject_types_for(programmatic_actor)
        when "Organization"
          Organization::Resources.subject_types_for(programmatic_actor)
        end

      ProgrammaticAccess::ResourceListHelpers.sort_by_displayed_titles(@resources)
    end
  end
end
