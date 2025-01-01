# typed: true
# frozen_string_literal: true

module Discussions
  class ManageSpotlightComponent < ApplicationComponent
    # timeline - a DiscussionTimeline
    def initialize(timeline:)
      @timeline = timeline
    end

    private

    attr_reader :timeline

    delegate :repository, :discussion, :repo_owner_login, :repo_name, :discussion_number, to: :timeline

    def render?
      timeline&.can_manage_spotlights?
    end

    memoize def repo_can_add_more_spotlights?
      !DiscussionSpotlight.repository_at_limit?(repository)
    end

    def spotlit?
      discussion_spotlight.present?
    end

    memoize def discussion_spotlight
      # Use the timeline.discussion_spotlights association
      # since it's already loaded (whereas discussion.spotlight would execute another query)
      repository.discussion_spotlights.detect do |spotlight|
        spotlight.discussion_id == discussion.id
      end
    end

    def discussion_spotlight_form_submit_path(discussion_spotlight)
      discussion_spotlight_path(repo_owner_login, repo_name, discussion_number, discussion_spotlight)
    end

    def edit_discussion_spotlight_form_content_path
      edit_discussion_spotlight_path(repo_owner_login, repo_name, discussion_number, discussion_spotlight)
    end

    def new_discussion_spotlight_form_submit_path
      discussion_spotlights_path(repo_owner_login, repo_name, discussion_number)
    end

    def new_discussion_spotlight_form_content_path
      new_discussion_spotlight_path(repo_owner_login, repo_name, discussion_number)
    end
  end
end
