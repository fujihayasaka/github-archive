# typed: true
# frozen_string_literal: true

module Reactions
  # Do not use this class directly in views, create your own reactions component
  # and generate the relevant arguments to render this component compositionally.
  #
  # See Reactions::ReactionsComponent
  class BaseComponent < ApplicationComponent
    extend T::Sig
    include CachedOcticonHelper

    # A slot that is a string displayed after the reaction buttons depending if the current user has reacted or not and how many unique reactors there are.
    # Accepts [system arguments](https://primer.style/view-components/system-arguments)
    renders_one :summary, ->(**system_arguments) do
      args = { tag: :div }.merge(system_arguments)
      Primer::BaseComponent.new(**T.unsafe(**args))
    end

    # Instantiates a Reaction::BaseComponent that includes renders all reactions for a target as well as the reaction popover to add more reactions.
    # @param target_global_relay_id [String] - uniquely identifies the target of the reaction (e.g. `release.global_relay_id`)
    # @param reaction_path [String] - path to the reaction endpoint
    # @param available_emotions [Array<Emotion>] - an array of Emotions possible to react with e.g. Discussion.emotions
    # @param viewer_reactions [Array<String>] - an array of reaction content strings that the viewer has reacted to e.g. ["smile", "heart"]
    # @param user_reactions [Hash { String => Integer, Array<String> }] - contains reactions as keys and an array of user logins OR a count of total user reactions as values. For example:
    #   {
    #     "tada" => 2
    #   }
    #   OR
    #   {
    #     "tada" => ["user1", "user2"]
    #   }
    # @param viewer_can_react [Boolean] _[Optional]_ - whether the user can react to the target. Defaults to `false`
    # @param show_reaction_selector [Boolean] _[Optional]_ - determines whether to render the reactions selector button and popover. Defaults to `true`
    # @param form_context [Hash] _[Optional]_ - A value to send via request body to the reaction endpoint as `params[:input][VALUE]`.
    #   {
    #     "context" => "feed",
    #     "showTop" => 2,
    #     "hideOcticon" => false
    #   }
    # @param reaction_target_identifier [String] - _[Optional]_ A string to add to the aria label for the reaction button. Defaults to `nil`
    # @param reaction_count_by_content [Hash] - _[Optional]_ A hash to override the count operation performed in #reactions_to_render, with emotions as keys and integers as values. Defaults to `{}`
    # @param selector_data [Hash] - _[Optional]_ A hash of data to add as data attributes to the reaction selector button. Defaults to `{}`
    # @param reaction_button_data [Hash] - _[Optional]_ A hash of data to add as data attributes to the reaction buttons. Defaults to `{}`
    # @param last_interacted_content [String] - _[Optional]_ The content of the last reaction emotion the user interacted with. Defaults to `nil`
    # @param **system_arguments _[Optional]_ - A Hash of [system arguments](https://primer.style/view-components/system-arguments) to be placed the reaction component
    def initialize(
      target_global_relay_id:,
      reaction_path:,
      available_emotions:,
      user_reactions:,
      viewer_reactions:,
      viewer_can_react: false,
      show_reaction_selector: true,
      form_context: {},
      reaction_target_identifier: nil,
      reaction_count_by_content: {},
      selector_data: {},
      reaction_button_data: {},
      popover_direction: Reactions::PopoverComponent::POPOVER_DIRECTION_DEFAULT,
      last_interacted_content: nil,
      **system_arguments
    )
      @last_interacted_content = last_interacted_content
      @target_global_relay_id = target_global_relay_id
      @reaction_path = reaction_path
      @available_emotions = available_emotions
      @user_reactions = user_reactions
      @viewer_reactions = viewer_reactions
      @viewer_can_react = viewer_can_react

      @show_reaction_selector = show_reaction_selector
      @form_context = form_context
      @reaction_target_identifier = reaction_target_identifier
      @reaction_count_by_content = reaction_count_by_content

      @selector_data = selector_data
      @reaction_button_data = reaction_button_data

      @popover_direction = popover_direction

      @system_arguments = system_arguments

      @system_arguments[:classes] = class_names(
        system_arguments[:classes],
        "js-reactions-container",
        "js-reaction-buttons-container",
        "social-reactions",
        "reactions-container",
        { "has-reactions" => has_reactions? }
      )

      @system_arguments[:display] = system_arguments[:display] || :flex
    end

    private

    attr_reader :target_global_relay_id,
      :reaction_path,
      :available_emotions,
      :form_context,
      :show_reaction_selector,
      :system_arguments,
      :popover_direction

    sig { returns T::Boolean }
    def has_reactions?
      @user_reactions.present?
    end

    # @param content [String] the string representation of the emotion
    # @return [Boolean] whether the current user has reacted to the target with the given emotion
    def reacted_to?(content)
      viewer_reactions.include?(content)
    end

    # @param emotion [Emotion] the emotion that has been reacted with
    # @param reactions [Integer, Array<String>] the number of reactions or an array of user logins
    # @return [String] A brief summary of how many reactions there are or who has reacted using the given emotion
    def title_for_popover(emotion, reactions)
      str = ""
      if reactions.is_a?(Integer)
        if reactions == 1 && viewer_reactions.include?(emotion.content)
          str += "You"
        else
          if viewer_reactions.include?(emotion.content)
            str += "You and "
            reactions = reactions - 1
          end
          str += "#{pluralize(reactions, 'person')}"
        end

        str += " reacted with #{emotion.pronounceable_label}"
        str
      elsif reactions.is_a?(Array)
        helpers.reaction_count_tooltip_for_model(
          emotion,
          reactions.take(ReactionsHelper::TOOLTIP_SOFT_TRUNCATION_THRESHOLD + 1),
          reactions.size,
        )
      end
    end

    # @param emotion [Emotion] the emotion that has been reacted with
    # @param count [Integer] the number of reactions for the emotion
    # @return [String] A descriptive string to be placed as an aria-label on the reaction button
    def aria_label_for_reaction_button(emotion, count)
      if @reaction_target_identifier.present?
        "#{emotion.pronounceable_label} (#{count}): #{@reaction_target_identifier}"
      else
        "#{(reacted_to?(emotion.content) ? "unreact" : "react")} with #{emotion.pronounceable_label}"
      end
    end

    # Maps all the user reactions for the target to a hash of attributes including the emotion, count, title, data attributes, and aria-label.
    # if @reaction_count_by_content is provided to the component, use the count entry instead (if for some reason the count of user logins differs from actual reaction count) see https://github.com/github/issues/issues/2532
    # @return [Array<Hash>] An array of hashes containing attributes to be used to render the reaction buttons
    sig { returns T::Array[T::Hash[Symbol, T.untyped]] }
    def reactions_to_render
      result = @available_emotions.filter do |emotion|
        @user_reactions.has_key?(emotion.content)
      end.collect do |emotion|
        # reactions will either be an integer or an array of user logins
        reactions = @user_reactions[emotion.content]

        raise ArgumentError.new(
          "Expected reactions value to either be an array of user logins or an integer, got #{reactions.class} instead"
        ) if !reactions.is_a?(Integer) && !reactions.is_a?(Array)

        count = reactions.is_a?(Integer) ? reactions : reactions.flatten.size

        if @reaction_count_by_content.present? && @reaction_count_by_content.has_key?(emotion.content)
          count = @reaction_count_by_content[emotion.content]
          title = helpers.reaction_count_tooltip_for_model(
            emotion,
            Array.wrap(reactions).take(ReactionsHelper::TOOLTIP_SOFT_TRUNCATION_THRESHOLD + 1),
            count,
          )
        end

        {
          emotion: emotion,
          count: count,
          data: @reaction_button_data,
          title: title || title_for_popover(emotion, reactions),
          aria: {
            label: aria_label_for_reaction_button(emotion, count),
          }
        }
      end

      if form_context[:showTop].present?
        result.sort { |a, b| b[:count] <=> a[:count] }.take(form_context[:showTop])
      else
        result
      end
    end

    sig { returns T.nilable(Integer) }
    def reactions_focus_index
      # Don't manage focus if no interaction has taken place.
      return if @last_interacted_content.nil?
      # Place focus on the ReactionSelector button, assuming it exists.
      return -1 if reactions_to_render.empty?

      last_interacted_content_present = reactions_to_render.any? { |reaction| reaction[:emotion].content == @last_interacted_content }
      last_interacted_content_new_index = last_interacted_content_present ? Emotion.find_index(@last_interacted_content) : nil
      # If the last interacted emotion is available, place focus on it.
      if last_interacted_content_new_index
        last_interacted_content_new_index
      else
        # Otherwise, determine the next available emotion from all the reactions_to_render
        emotions_to_render = reactions_to_render.map { |reaction| reaction[:emotion] }
        filtered_emotions = available_emotions.filter { |emotion| emotions_to_render.include?(emotion) || emotion.content == @last_interacted_content }
        filtered_emotions_last_interacted_index = filtered_emotions.find_index { |emotion| emotion.content == @last_interacted_content }

        next_emotion = filtered_emotions[filtered_emotions_last_interacted_index + 1]
        if next_emotion
          reactions_focus_index = Emotion.find_index(next_emotion.content)
        else
          previous_emotion = filtered_emotions[filtered_emotions_last_interacted_index - 1]
          reactions_focus_index = Emotion.find_index(previous_emotion.content)
        end
        reactions_focus_index
      end
    end

    # @return [Array] Returns an empty array if not logged in, otherwise returns an array of strings that contain the current user's reactions
    sig { returns T::Array[String] }
    def viewer_reactions
      return [] unless logged_in?

      @viewer_reactions
    end

    sig { returns T::Boolean }
    def viewer_can_react?
      return false unless logged_in?
      @viewer_can_react
    end
  end
end
