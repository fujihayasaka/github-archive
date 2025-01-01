# typed: true
# frozen_string_literal: true

# Shared methods for use in any view component that renders Reactions::BaseComponent.
# See Reactions::ReactionsComponent as an example.
module Reactions::BaseComponentHelpers
  extend T::Helpers
  extend T::Sig

  requires_ancestor { Kernel }
  requires_ancestor { ApplicationComponent }

  class MissingTargetError < StandardError; end

  # The target of the reactions component.
  # Required for all methods in this module.
  #
  # Returns ActiveRecord object that implements the Reactable interface, or
  # Adapter object that implements the PlatformTypes::Reactable interface, or
  # raises error if target instance variable is undefined
  def target
    raise MissingTargetError unless defined?(@target)
    @target
  end

  # Default classnames to include on the outermost element of the Reactions::BaseComponent
  sig { returns String }
  def default_reactions_classes
    "comment-reactions"
  end

  # A map of user logins by reaction.
  #
  # Returns Hash with emotion content strings as keys and arrays of user login strings as values.
  # ex. {"smile"=>["monalisa", "octocat"], "heart"=>["monalisa"]}
  def reactions
    return @_reactions if defined?(@_reactions)
    @_reactions = target.prelude_user_logins_by_reaction
  end

  # A list of allowed emotions
  #
  # Note on class versus instance `emotions` interface:
  #   - If target is an ActiveRecord object, then it's expected to implement the Reactable interface,
  #     which implements a class method `emotions`.
  #   - If target is an Adapter object, then its emotions are only available at the instance level.
  #     See `Issue::Adapter::BaseCommentAdapter`.
  #   - The ternary check below can be simplified to only call the class method after all Adapters
  #     have been removed. See https://github.com/github/issues/issues/2107.
  #
  # Returns enumerable collection of Emotion objects
  def emotions
    return @_emotions if defined?(@_emotions)
    @_emotions = target.respond_to?(:emotions) ? target.emotions : target.class.emotions
  end

  # Does the target have any reactions?
  sig { returns T::Boolean }
  def has_reactions?
    reactions.any?
  end

  # Has the current user reacted to the target?
  sig { returns T::Boolean }
  def has_reacted?
    reactions_viewer_has_reacted_to.any?
  end

  # A list of reactions that the current user has made to the target.
  #
  # Returns Array of emotion content strings (ex. ["smile"])
  sig { returns T::Array[String] }
  def reactions_viewer_has_reacted_to
    return [] unless logged_in?
    @_reactions_viewer_has_reacted_to ||= reactions.filter_map do |content, user_logins|
      content if user_logins.include?(current_user.display_login)
    end
  end

  # A string to add to the aria label for the reaction button.
  #
  # Returns String or nil (ex. "monalisa, 05:28AM on December 30, 2015")
  sig { returns T.nilable(String) }
  def reaction_target_identifier
    return if !has_reactions?
    format = aria_label_date(target.created_at)
    login = (target.try(:user) || User.ghost).display_login
    "#{login}, #{target.created_at.to_formatted_s(format)}"
  end

  # Can the current user add a reaction to the target?
  sig { returns T::Boolean }
  def viewer_can_react?
    return false unless logged_in?
    return @_viewer_can_react if defined?(@_viewer_can_react)

    @_viewer_can_react = begin
      if target.respond_to?(:prelude_viewer_can_react)
        target.prelude_viewer_can_react(current_user)
      else
        target.async_reactable_by?(current_user).sync
      end
    end
  end
end
