# typed: true
# frozen_string_literal: true

module Comments
  class ReactionsWithContextComponent < ApplicationComponent
    # Instantiates a Comments::ReactionsWithContextComponent that renders all reactions for the given target.
    #
    # PLANNED FOR DEPRECATION
    # AVOID USAGE OR MODIFICATION OF THIS FILE
    #
    # Consider using one of these closely related view components as an alternative:
    #  - DashboardFeed::ReactionsComponent
    #  - Discussions::ReactionsComponent
    #  - PullRequests::ReactionsComponent
    #  - Reactions::ReactionsComponent
    #
    # target_global_relay_id - Global relay id for target, where target is an ActiveRecord object that implements the
    #                          Reactable interface, or Adapter object that implements the PlatformTypes::Reactable interface
    # reaction_path - String path to the reaction CRUD endpoint
    # viewer_reactions - Array of reaction content strings that the viewer has reacted to e.g. ["smile", "heart"]
    # available_emotions - enumerable collection of Emotion objects
    # user_reactions - Hash with reaction content strings as keys and an array of user logins OR a count of total user
    #                  reactions as values. For example,  {"tada" => 2} OR {"tada" => ["user1", "user2"]}
    # reaction_count_by_content - Hash to override the default count operation, with reaction content as keys and
    #                             integers as values. For example, {"tada" => 2}
    # viewer_can_react - Boolean, indicates whether the viewer has permissions to react to the target
    # context (optional) - String to send via request body to the reaction endpoint as `params[:input][:context]`
    def initialize(
      target_global_relay_id:,
      reaction_path:,
      viewer_reactions:,
      available_emotions:,
      user_reactions:,
      reaction_count_by_content:,
      viewer_can_react:,
      context: nil
    )
      @target_global_relay_id = target_global_relay_id
      @reaction_path = reaction_path
      @viewer_reactions = viewer_reactions
      @available_emotions = available_emotions
      @user_reactions = user_reactions
      @reaction_count_by_content = reaction_count_by_content
      @viewer_can_react = viewer_can_react
      @context = context
    end

    attr_reader :target_global_relay_id, :reaction_path, :viewer_reactions, :available_emotions, :user_reactions, :reaction_count_by_content, :viewer_can_react, :context

    def call
      render Reactions::BaseComponent.new(
        form_context: { context: context },
        target_global_relay_id: target_global_relay_id,
        reaction_path: reaction_path,
        available_emotions: available_emotions,
        viewer_reactions: viewer_reactions,
        user_reactions: user_reactions,
        reaction_count_by_content: reaction_count_by_content,
        viewer_can_react: viewer_can_react,
        show_reaction_selector: show_reaction_selector?,
        display: [(:none unless show_reaction_selector?), nil, (:flex if show_reaction_selector?), nil, nil],
        classes: "comment-reactions"
      )
    end

    private

    def is_context_feed?
      context == ReactionsController::FEED_CONTEXT
    end

    def has_reactions?
      user_reactions.any?
    end

    def show_reaction_selector?
      is_context_feed? || has_reactions?
    end
  end
end
