# typed: strict
# frozen_string_literal: true

class Growth::TipComponent < ApplicationComponent
  DEFAULT_DISMISSIBLE = T.let(:none, Symbol)
  DISMISSIBLE_TYPE_VALUES = T.let([:user, :none].freeze, T::Array[Symbol])

  sig { returns T::Hash[Symbol, T.untyped] }
  attr_reader :system_arguments

  sig { returns T.nilable(User) }
  attr_reader :user

  sig { returns T.nilable(String) }
  attr_reader :notice_name

  sig { returns Symbol }
  attr_reader :dismissible_type

  sig do
    params(
      dismissible_type: Symbol,
      notice_name: T.nilable(String),
      user: T.nilable(User),
      system_arguments: T.untyped
    ).void
  end
  def initialize(dismissible_type: :none, notice_name: nil, user: nil, **system_arguments)
    @dismissible_type = T.let(fetch_or_fallback(DISMISSIBLE_TYPE_VALUES, dismissible_type, DEFAULT_DISMISSIBLE), Symbol)
    @user = user
    @notice_name = notice_name
    @system_arguments = system_arguments
    @system_arguments[:classes] = class_names({ "js-notice": @dismissible_type != :none }, @system_arguments[:classes])
  end

  sig { returns T::Boolean }
  def render?
    case @dismissible_type
    when :user
      return false unless @user.present?
      return false if @user.dismissed_notice?(@notice_name)
    end
    true
  end

  renders_one :description, lambda { |**system_arguments|
    arguments = system_arguments
    arguments[:tag] = :p unless arguments.key?(:tag)
    arguments[:mb] = 0 unless arguments.key?(:mb)
    arguments[:mr] = 4 unless arguments.key?(:mr)
    Primer::BaseComponent.new(
      **arguments
    )
  }

  renders_one :action, lambda { |**system_arguments|
    arguments = system_arguments
    Primer::Beta::Button.new(
      **arguments
    )
  }

  renders_one :dismiss_button, lambda { |**system_arguments|
    arguments = system_arguments
    arguments[:icon] = :x
    arguments[:scheme] = :invisible unless arguments.key?(:scheme)
    arguments[:type] = :submit
    arguments[:show_tooltip] = false
    arguments[:ml] = 2 unless arguments.key?(:ml)
    arguments[:top] = 0
    arguments[:right] = 0
    arguments[:"aria-label"] = "Dismiss tip"
    arguments[:position] = [:relative, :absolute, :absolute, :relative, :relative] unless arguments.key?(:position)
    Primer::Beta::IconButton.new(
      **arguments
    )
  }
end
