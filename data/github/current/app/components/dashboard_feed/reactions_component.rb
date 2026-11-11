# typed: true
# frozen_string_literal: true

module DashboardFeed
  class ReactionsComponent < ApplicationComponent
    # Instantiates a DashboardFeed::ReactionsComponent that renders all reactions for the given target.
    #
    # See also these closely related view components:
    #  - Comments::ReactionsComponent
    #  - Discussions::ReactionsComponent
    #  - PullRequests::ReactionsComponent
    #  - Reactions::ReactionsComponent
    #
    # target_global_relay_id - Global relay id for target, where target is an ActiveRecord object that implements the
    #                          Reactable interface, or Adapter object that implements the PlatformTypes::Reactable interface
    # reaction_path - String path to the reaction CRUD endpoint
    # emotions - enumerable collection of Emotion objects
    # reaction_count_by_content - Hash to override the default count operation, with reaction content as keys and
    #                             integers as values. For example, {"tada" => 2}
    # viewer_reaction_contents - Array of reaction content strings that the viewer has reacted to e.g. ["smile", "heart"]
    # emotion_data (optional) -  Hash of data to add as data attributes to the reaction buttons
    #                            (e.g. for click tracking)
    # selector_data (optional) - Hash of data to add as data attributes to the reaction selector button
    #                            (e.g. for click tracking)
    # form_context (optional) - Hash of various items you wish to pass in.  It will always include context: ReactionsController::FEED_CONTEXT
    #
    def initialize(
      target_global_id:,
      reaction_path:,
      emotions:,
      reaction_count_by_content:,
      viewer_reaction_contents:,
      emotion_data: {},
      show_reaction_selector: true,
      selector_data: {},
      form_context: {}
    )
      @target_global_id = target_global_id
      @reaction_path = reaction_path
      @emotions = emotions
      @reaction_count_by_content = reaction_count_by_content
      @viewer_reaction_contents = viewer_reaction_contents
      @emotion_data = emotion_data
      @selector_data = selector_data
      @show_reaction_selector = show_reaction_selector
      @form_context = form_context
      @popover_direction = "ne"
    end

    def call
      render Reactions::BaseComponent.new(
        target_global_relay_id: @target_global_id,
        reaction_path: @reaction_path,
        available_emotions: @emotions,
        viewer_reactions: @viewer_reaction_contents,
        user_reactions: @reaction_count_by_content,
        form_context: { context: ReactionsController::FEED_CONTEXT }.merge(@form_context),
        viewer_can_react: viewer_can_react?,
        selector_data: @selector_data,
        reaction_button_data: @emotion_data,
        show_reaction_selector: @show_reaction_selector,
        ml: @show_reaction_selector ? 0 : 3,
        popover_direction: @popover_direction,
      )
    end

    def viewer_can_react?
      logged_in?
    end
  end
end
