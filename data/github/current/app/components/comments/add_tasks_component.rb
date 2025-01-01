# typed: true
# frozen_string_literal: true

module Comments
  class AddTasksComponent < ApplicationComponent
    attr_reader :issue, :textarea_id, :viewer, :classes

    # @param issue [Issue] the issue we will add tasks into
    # @param textarea_id [String] element ID used in the JS side for actually adding the new task block
    # @param viewer [User] the user who is viewing the page
    # @param classes [String] html classes to append to element
    # @param system_arguments [Hash] See https://primer.style/view-components/system-arguments
    def initialize(issue, textarea_id, viewer, classes = nil, **system_arguments)
      @issue = issue
      @textarea_id = textarea_id
      @viewer = viewer
      @classes = classes
      @system_arguments = system_arguments

      @system_arguments[:tag] = "tasklist-block-add-tasklist"
      @system_arguments[:display] = :inline_flex
      @system_arguments[:font_size] = :small
      @system_arguments[:ml] ||= 3
      @system_arguments[:style] = "height: 27px;"
      @system_arguments[:classes] = class_names(
        "flex-row",
        "flex-items-center",
        system_arguments[:classes]
      )
    end

    def render?
      return false if issue.nil? || !issue.is_a?(Issue) || issue.pull_request?
      return false if viewer.nil?
      return false if !(with_database_error_fallback(fallback: false) { issue.viewer_can_update? viewer })

      owner = issue.repository.owner
      return false if owner.nil?
      feature_enabled_globally_or_for_current_user_or_entity?(:tasklist_block, owner)
    end

    private

    delegate :feature_enabled_globally_or_for_current_user_or_entity?, to: :helpers

    def button_classes
      class_names(
        "js-add-tasklist-body-button",
        classes
      )
    end

    def hydro_attributes
      hydro_click_tracking_attributes("add_tasklist.click", {
        issue_id: issue.id,
      })
    end
  end
end
