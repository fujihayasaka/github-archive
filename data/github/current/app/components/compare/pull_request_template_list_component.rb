# typed: true
# frozen_string_literal: true

module Compare
  class PullRequestTemplateListComponent < ApplicationComponent
    include EnterpriseManagedUsersHelper
    include CurrentRepositoryInteractionsHelper
    include HydroHelper

    attr_reader :current_repository, :range, :current_user, :comparison

    def initialize(current_repository:, range:, current_user:, comparison:)
      @current_repository = current_repository
      @range = range
      @current_user = current_user
      @comparison = comparison
    end

    def render?
      pull_request_templates&.any? && pull_request_templates.count > 1
    end

    memoize def pull_request_templates
      current_repository&.pull_request_templates
    end

    def formatted_filename(filename)
      filename.sub(/(?<=.)\..*/, " ").split("_").join(" ").rstrip.capitalize
    end

    memoize def blank_pull_request_hydro_attributes
      click_tracking_attributes("show_pull_request_form")
    end

    memoize def template_pull_request_hydro_attributes
      click_tracking_attributes("show_pull_request_form_with_templates")
    end

    def click_tracking_attributes(action)
      payload = {
        user_id: current_user&.id,
        repository_id: current_repository&.id,
        category: "compare_show",
        data: comparison.click_tracking_attributes,
        action: action
      }
      hydro_click_tracking_attributes("pull_request.user_action", payload)
    end
  end
end
