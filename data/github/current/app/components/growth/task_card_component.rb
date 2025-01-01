# typed: strict
# frozen_string_literal: true

# Use this for onboarding tasks that:
# - Do not track done state
# - Have more than one action. For example a title link, and button call to action.
#
# Note that because we allow multiple actions, the entire card is not clickable like other tasks.
module Growth
  class TaskCardComponent < ApplicationComponent
    sig { returns T::Hash[Symbol, T.untyped] }
    attr_reader :system_arguments

    sig { params(system_arguments: Primer::SystemArgumentsValue).void }
    def initialize(**system_arguments)
      @system_arguments = system_arguments
      @system_arguments[:display] = :flex unless system_arguments.key?(:display)
      @system_arguments[:direction] = :column unless system_arguments.key?(:direction)
      @system_arguments[:border] = true unless system_arguments.key?(:border)
      @system_arguments[:border_radius] = 2 unless system_arguments.key?(:border_radius)
      @system_arguments[:p] = 3 unless system_arguments.key?(:p)
      @system_arguments[:align_items] = :flex_start unless system_arguments.key?(:align_items)
      @system_arguments[:style] = "height: 100%;" unless system_arguments.key?(:style)
    end

    renders_one :title, lambda { |**system_arguments|
      arguments = system_arguments
      arguments[:font_weight] = :bold unless arguments.key?(:font_weight)
      Primer::Beta::Link.new(
        **arguments,
      )
    }

    renders_one :action, lambda { |**system_arguments|
      arguments = system_arguments
      arguments[:size] = :small unless arguments.key?(:size)
      arguments[:mt] = 3 unless arguments.key?(:mt)
      Primer::Beta::Button.new(
        **arguments
      )
    }

    renders_one :description, lambda { |**system_arguments|
      arguments = system_arguments
      arguments[:tag] = :p unless arguments.key?(:tag)
      arguments[:font_size] = 6 unless arguments.key?(:font_size)
      arguments[:color] = :muted unless arguments.key?(:color)
      arguments[:mb] = 0 unless arguments.key?(:mb)
      Primer::BaseComponent.new(
        **arguments
      )
    }
  end
end
