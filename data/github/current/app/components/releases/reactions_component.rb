# typed: true
# frozen_string_literal: true

module Releases
  class ReactionsComponent < ApplicationComponent
    include Reactions::BaseComponentHelpers

    # Instantiates a Releases::ReactionsComponent that renders all reactions for the given target,
    # as well as an optional summary.
    #
    # target - ActiveRecord object that implements the Reactable interface, or Adapter object that implements the
    #          PlatformTypes::Reactable interface
    # include_summary (optional) - Boolean, determines whether string summary will be displayed after reaction buttons.
    # last_interacted_content (optional) - String, the value of the emotion of the reaction that was last added/removed
    def initialize(target:, include_summary: false, last_interacted_content: nil)
      @target = target
      @include_summary = include_summary
      @last_interacted_content = last_interacted_content
    end

    def call
      render Reactions::BaseComponent.new(
        viewer_reactions: reactions_viewer_has_reacted_to,
        available_emotions: emotions,
        reaction_path: target.reaction_path,
        target_global_relay_id: target.global_relay_id,
        user_reactions: reactions,
        viewer_can_react: viewer_can_react?,
        reaction_target_identifier: reaction_target_identifier,
        classes: default_reactions_classes,
        popover_direction: "ne",
        last_interacted_content: @last_interacted_content,
      ) do |c|
        if @include_summary
          c.with_summary(
            color: :muted,
            mt: 1,
            test_selector: "reactions-summary"
          ) { string_for_summary }
        end
      end
    end

    private

    def include_summary?
      @include_summary
    end

    memoize def unique_reactor_count
      reactions.values.flatten.uniq.count
    end

    def other_reactor_count
      return unique_reactor_count unless logged_in?

      @other_reactor_count ||= has_reacted? ? unique_reactor_count - 1 : unique_reactor_count
    end

    def string_for_summary
      str = ""
      if has_reacted?
        str = "You"
        if other_reactor_count > 0
          str += " and #{helpers.discussion_social_count other_reactor_count} #{'other'.pluralize(other_reactor_count)}"
        end
        str += " reacted"
      elsif unique_reactor_count > 0
        str += "#{helpers.discussion_social_count unique_reactor_count} #{"person".pluralize(unique_reactor_count)} reacted"
      end
      str
    end
  end
end
