# typed: true
# frozen_string_literal: true

module Reactions
  class ReactionsComponent < ApplicationComponent
    include Reactions::BaseComponentHelpers

    # Instantiates a Reactions::ReactionsComponent that renders all reactions for the given target.
    #
    # target - ActiveRecord object that implements the Reactable interface, or Adapter object that implements the
    #          PlatformTypes::Reactable interface
    def initialize(target:)
      @target = target
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
        classes: default_reactions_classes
      )
    end
  end
end
