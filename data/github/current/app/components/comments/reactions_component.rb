# typed: true
# frozen_string_literal: true

module Comments
  class ReactionsComponent < ApplicationComponent
    include Reactions::BaseComponentHelpers

    # Instantiates a Comments::ReactionsComponent that renders all reactions for the given target.
    # Only renders selector button if target has existing reactions, or when rendered within a feed context.
    #
    # target - ActiveRecord object that implements the Reactable interface, or Adapter object that implements the
    #          PlatformTypes::Reactable interface
    # context (optional) - String to send via request body to the reaction endpoint as `params[:input][:context]`
    #                      Only relevant when rendered within a feed.
    # **system_arguments (optional) - A Hash of [system arguments](https://primer.style/view-components/system-arguments)
    #                                 to be passed to the reaction component
    def initialize(target:, context: nil, **system_arguments)
      @target = target
      @context = context
      @system_arguments = system_arguments
    end

    def call
      classes = []
      classes << default_reactions_classes
      classes << @system_arguments[:classes]
      classes << "just-bottom" if FeatureFlag.vexi.enabled?(:reactions_position, current_user, default: false)

      render T.unsafe(Reactions::BaseComponent).new(
        form_context: { context: @context },
        target_global_relay_id: target.global_relay_id,
        reaction_path: target.reaction_path,
        available_emotions: emotions,
        viewer_reactions: reactions_viewer_has_reacted_to,
        user_reactions: reactions,
        viewer_can_react: viewer_can_react?,
        show_reaction_selector: show_reaction_selector?,
        display: show_reaction_selector? ? :flex : :none,
        classes: classes,
        popover_direction: "ne",
        **@system_arguments
      )
    end

    private

    memoize def show_reaction_selector?
      return true if FeatureFlag.vexi.enabled?(:reactions_position, current_user, default: false)
      is_context_feed? || has_reactions?
    end

    # TODO: extract "context" related logic into a separate feed-specific view component, because it's
    # only relevant for the specific, limited case when this component is rendered within a feed.
    def is_context_feed?
      @context == ReactionsController::FEED_CONTEXT
    end
  end
end
