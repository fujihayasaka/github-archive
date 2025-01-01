# typed: false
# frozen_string_literal: true

module Events
  class CreateView < View
    include UrlHelper

    def title_text
      parts = [pusher_text, pusher_bot_identifier_text, "created a", object, object_name,
               in_repository_text]
      parts.compact.join(" ")
    end

    # Returns 'branch', 'tag', or 'repository'.
    def object
      ref_type || super || "repository"
    end

    def icon
      if branch?
        "git-branch"
      elsif tag?
        "tag"
      else # repo
        "repo"
      end
    end

    def show_event_details?(viewer:)
      repository? && repo_description.present?
    end

    def branch?
      object == "branch"
    end

    def repository?
      object == "repository"
    end

    def object_name
      ref || payload[:object_name] || repo_name || "deleted"
    end

    def tree_path
      path  = "/#{repo_nwo}".dup
      path << "/tree/#{escape_url_branch(object_name)}" unless repository?
      path
    end

    # Public: Returns a string for use with #analytics_attributes_for to describe the
    # target for a link to the object that was created in this event (a repository,
    # a branch, or a tag).
    def analytics_target
      if branch?
        "branch link"
      else
        action_target
      end
    end

    def action_target
      return "repository" if object == "repo"
      object
    end

    private

    def in_repository_text
      unless repository?
        "in #{repo_text}"
      end
    end

    def repo_name
      parts = [user[:login], repo[:name]]
      parts.compact!
      if parts.empty?
        repository.try(:name_with_owner) || "unknown"
      else
        parts.join("/")
      end
    end

    def tag?
      object == "tag"
    end
  end
end
