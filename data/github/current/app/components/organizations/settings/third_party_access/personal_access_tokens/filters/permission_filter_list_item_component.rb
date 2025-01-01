# typed: true
# frozen_string_literal: true

module Organizations::Settings::ThirdPartyAccess::PersonalAccessTokens::Filters
  class PermissionFilterListItemComponent < ApplicationComponent
    attr_reader :metadata

    attr_reader :resource, :action, :selected_permission

    def initialize(resource:, action:, selected_permission:)
      @resource = resource
      @action = action
      @selected_permission = selected_permission
    end

    def permission
      "#{resource}_#{action}"
    end

    memoize def title
      Permissions::FineGrainedResources::Metadata.new(@resource).title
    end

    def is_selected?
      return false if selected_permission.nil?

      selected_resource, selected_action = selected_permission.first
      permission == "#{selected_resource}_#{selected_action}"
    end
  end
end
