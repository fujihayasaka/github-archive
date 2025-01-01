# typed: true
# frozen_string_literal: true

module FeedPosts
  class DialogComponent < ApplicationComponent
    # Renders a dialog component that allows a user to create a new feed post.
    # @param **system_arguments _[Optional]_ - A Hash of [system arguments](https://primer.style/view-components/system-arguments) or Primer::Experimental::Dialog arguments to be placed the `<modal-dialog>` element.
    def initialize(**system_arguments)
      @system_arguments = system_arguments

      @system_arguments[:classes] = class_names(
        system_arguments[:classes],
        "dashboard-feed-post-dialog-component"
      )
    end

    attr_reader :system_arguments

    def new_feed_post
      FeedPost.new
    end

    memoize def topics
      current_user.starred_topics.limit(User::PinnedFeedsDependency::MAX_STARRED_TOPICS)
    end

    memoize def active_topic
      return nil unless params[:topic]

      topics.find_by(name: params[:topic])
    end

    memoize def embeds_enabled?
      GitHub.flipper[:feed_post_embeds].enabled?(current_user)
    end
  end
end
