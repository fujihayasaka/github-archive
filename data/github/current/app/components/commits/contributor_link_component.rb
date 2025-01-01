# typed: true
# frozen_string_literal: true

module Commits
  class ContributorLinkComponent < ApplicationComponent
    attr_reader :git_actor

    def initialize(git_actor:)
      @git_actor = git_actor
    end

    def call
      if actor
        link_to(
          actor.display_login,
          commits_resource_path.to_s,
          class: classes,
          title: "View all commits by #{actor.display_login}",
          data: hovercard_data_attributes_for_user_login(actor.display_login),
        )
      else
        title = git_actor.name.presence || "Oops! This commit is missing contributor information."
        content_tag(:span, class: classes, title: title, href: commits_resource_path) { git_actor_name }
      end
    end

    memoize def git_actor_name
      git_actor.name.presence || "Unknown"
    end

    def classes
      "commit-author user-mention"
    end

    memoize def actor
      if git_actor.is_a?(User)
        git_actor
      else
        git_actor.async_visible_actor(current_user).sync
      end
    end

    def commits_resource_path
      if git_actor.is_a?(User)
        nil
      else
        git_actor.async_commits_path_uri.sync
      end
    end
  end
end
