# typed: true
# frozen_string_literal: true

module Discussions
  class ReactionsComponent < ApplicationComponent
    include Reactions::BaseComponentHelpers

    # Instantiates a Discussions::ReactionsComponent that renders all reactions for the given target.
    #
    # target - ActiveRecord object that implements the Reactable interface, or Adapter object that implements the
    #          PlatformTypes::Reactable interface
    # last interacted content - String, optional, the content of the last reaction the user picked
    def initialize(target:, last_interacted_content: nil)
      @target = target
      @last_interacted_content = last_interacted_content
    end

    def call
      render Reactions::BaseComponent.new(
        viewer_reactions: reactions_viewer_has_reacted_to,
        available_emotions: emotions,
        reaction_path: target.reaction_path,
        target_global_relay_id: target.global_relay_id,
        user_reactions: reactions,
        show_reaction_selector: show_reaction_selector?,
        viewer_can_react: viewer_can_react?,
        ml: 2,
        classes: default_reactions_classes,
        popover_direction: "ne",
        last_interacted_content: @last_interacted_content,
      )
    end

    private

    def show_reaction_selector?
      true
    end

    memoize def comment_is_nested?
      target.is_a?(DiscussionComment) && target.nested?
    end
  end
end
