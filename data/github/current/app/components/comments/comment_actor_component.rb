# typed: strict
# frozen_string_literal: true

module Comments
  class CommentActorComponent < ApplicationComponent
    include BotHelper

    sig { returns(T.nilable(User)) }
    attr_reader :actor

    sig { returns(T::Boolean) }
    attr_reader :show_full_name

    sig { returns(String) }
    attr_reader :link_class

    sig { returns(T.nilable(Configurable::UserNameDisplayConfiguration)) }
    attr_reader :target_for_user_name_display_configuration

    # Initializes the CommentActorComponent with an actor and display options.
    #
    # @param actor [nil, User] The user/actor to display. If nil, @ghost will be rendered.
    # @param show_full_name [Boolean] Whether to show the actor's full name instead of username. Defaults to false.
    # @param target_for_user_name_display_configuration [nil, Configurable::UserNameDisplayConfiguration]
    #    Configurable model to consult for configuration for user name display, such as an Organization. If provided,
    #    this object's user name display preference will be used to determine how to render the actor's name within
    #    the profile link. If nil, a handle-only display will be used. Takes precedence over show_full_name.
    # @param link_class [String] Additional CSS classes to apply to the actor link.
    sig do
      params(
        actor: T.nilable(User),
        show_full_name: T.nilable(T::Boolean),
        target_for_user_name_display_configuration: T.nilable(Configurable::UserNameDisplayConfiguration),
        link_class: String
      ).void
    end
    def initialize(actor:, show_full_name: false, target_for_user_name_display_configuration: nil, link_class: "")
      @actor = actor
      @show_full_name = T.let(!!show_full_name, T::Boolean)
      @target_for_user_name_display_configuration = target_for_user_name_display_configuration
      @link_class = link_class
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def link_options
      {
        class: "author Link--primary text-bold css-overflow-wrap-anywhere #{link_class}",
        show_full_name: show_full_name,
        user_name_display_configuration: target_for_user_name_display_configuration&.eligible_for_user_name_display_configuration? || false,
      }
    end
  end
end
