# typed: false
# frozen_string_literal: true

# Decorates a Stratocaster::Attributes::Release event with view logic.
#
# Examples
#
#   # equivalent ways to render the event's html
#   render_event(Events::ReleaseView.new(event))
#
#   # or
#   render_event(Events::View.for(event))
module Events
  class ReleaseView < View
    include UrlHelpers

    def title_text
      parts = [actor_text, actor_bot_identifier_text, "released", release_title, "at", repo_text]
      parts.compact.join(" ")
    end

    def release_title
      release_name || release_tag_name
    end

    def release_path
      return unless repo_owner_login && repo_name && release_tag_name

      show_release_path repo_owner_login, repo_name, release_tag_name
    end

    def visible_assets
      assets.take(max_assets)
    end

    def asset_count
      assets.size
    end

    def more_assets?
      (asset_count > max_assets)
    end

    def sponsor_button_target_user_id
      repo_owner_id
    end

    def sponsor_button_target_user_login
      repo_owner_login
    end

    private

    def repo_owner_login
      user[:login]
    end

    def repo_owner_id
      user[:id]
    end

    def repo_name
      repo[:name]
    end

    def assets
      release_assets
    end

    def max_assets
      2
    end
  end
end
