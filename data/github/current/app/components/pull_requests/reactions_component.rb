# typed: true
# frozen_string_literal: true

module PullRequests
  class ReactionsComponent < ApplicationComponent
    include Reactions::BaseComponentHelpers

    attr_reader :popover_direction
    # Instantiates a PullRequests::ReactionsComponent that renders all reactions for the given target.
    #
    # target - ActiveRecord object that implements the Reactable interface, or Adapter object that implements the
    #          PlatformTypes::Reactable interface
    # popover_direction - String direction to render the popover in. Defaults to Reactions::PopoverComponent::POPOVER_DIRECTION_DEFAULT
    def initialize(target:, popover_direction: Reactions::PopoverComponent::POPOVER_DIRECTION_DEFAULT)
      @target = target
      @popover_direction = popover_direction
    end

    def call
      classes = [default_reactions_classes]
      classes << "just-bottom" if GitHub.flipper[:reactions_position].enabled?(current_user)
      render Reactions::BaseComponent.new(
        viewer_reactions: reactions_viewer_has_reacted_to,
        available_emotions: emotions,
        reaction_path: target.reaction_path,
        target_global_relay_id: target.global_relay_id,
        user_reactions: reactions,
        show_reaction_selector: has_reactions? || GitHub.flipper[:reactions_position].enabled?(current_user),
        viewer_can_react: viewer_can_react?,
        reaction_target_identifier: reaction_target_identifier,
        classes: classes,
        popover_direction: popover_direction
      )
    end
  end
end
