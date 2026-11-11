# typed: true
# frozen_string_literal: true

module Discussions
  class LabelsMenuContentComponent < ApplicationComponent
    # viewer_can_push - optional Boolean indicating whether the authenticated user has push access to the repo,
    #                   if known; if nil is passed, the actual value will be looked up
    def initialize(repository:, discussion:, viewer_can_push: nil)
      @repository = repository
      @discussion = discussion
      @viewer_can_push = viewer_can_push
    end

    private

    attr_reader :discussion, :repository

    def labels
      @repository.sorted_labels(issue_or_pr: discussion, cache_label_html: true)
    end

    memoize def selected_label_ids
      Set.new(discussion.label_ids)
    end

    def selected?(label)
      selected_label_ids.include?(label.id)
    end

    def form_action_path
      discussions_labels_path(@repository.owner_display_login, @repository.name, number: discussion.number)
    end

    def manage_labels_path
      issues_labels_path(@repository.owner_display_login, @repository.name)
    end

    def viewer_can_push?
      if @viewer_can_push.nil?
        @repository.pushable_by?(current_user)
      else
        @viewer_can_push
      end
    end

    memoize def can_manage_labels?
      @repository.writable? && viewer_can_push?
    end
  end
end
