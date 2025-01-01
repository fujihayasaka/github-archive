# typed: true
# frozen_string_literal: true

module Discussions
  class LabelsComponent < ApplicationComponent
    include LabelsHelper

    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    sig do
      params(
        timeline: T.untyped,
        defer_menu_content: T.untyped,
        org_param: T.nilable(String)
      ).returns(LabelsComponent)
    end
    def self.for_timeline(timeline, defer_menu_content: true, org_param: nil)
      new(
        repository: timeline.repository,
        discussion: timeline.discussion,
        can_edit_labels: timeline.can_edit_labels?,
        defer_menu_content: defer_menu_content,
        viewer_can_push: timeline.viewer_can_push?,
        org_param: org_param,
      )
    end

    # viewer_can_push - optional Boolean indicating whether the authenticated user has push access to the repo
    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    sig do
      params(
        repository: T.untyped,
        discussion: T.untyped,
        can_edit_labels: T.untyped,
        defer_menu_content: T.untyped,
        viewer_can_push: T.nilable(T::Boolean),
        parsed_discussions_query: T.untyped,
        org_param: T.nilable(String)
      ).void
    end
    def initialize(repository:, discussion:, can_edit_labels:, defer_menu_content: true, viewer_can_push: nil, parsed_discussions_query: [], org_param: nil)
      @repository = repository
      @discussion = discussion
      @can_edit_labels = fetch_or_fallback([true, false], can_edit_labels, false)
      @defer_menu_content = fetch_or_fallback([true, false], defer_menu_content, true)
      @viewer_can_push = viewer_can_push
      @parsed_discussions_query = parsed_discussions_query
      @org_param = org_param
    end

    def render?
      repository.present? && discussion.present?
    end

    private

    attr_reader :repository, :discussion, :parsed_discussions_query

    sig { returns T.nilable(String) }
    attr_reader :org_param

    def current_repository
      repository
    end

    def labels
      discussion.labels
    end

    def viewer_can_push?
      @viewer_can_push
    end

    def can_edit_labels?
      @can_edit_labels
    end

    def defer_menu_content?
      @defer_menu_content
    end

    def deferred_menu_path
      url_params = { number: discussion.number }

      # If this is a new discussion being created, we have to pass in the selected labels from
      # PrefilledDiscussionFields so that we know to mark these labels as selected when loading
      # the deferred menu.
      if discussion.new_record? && labels.any?
        url_params = url_params.merge({
          discussion: { labels: labels.map(&:id) }
        })
      end

      discussions_labels_path(
        repository.owner_display_login,
        repository.name,
        url_params
      )
    end

    def rerender_component_path
      sidebar_item_discussions_labels_path(repository.owner_display_login, repository.name)
    end
  end
end
