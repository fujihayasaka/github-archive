# typed: true
# frozen_string_literal: true
module Primer
  module Experimental
    module SelectMenu
      class SummaryComponent < Primer::Component # rubocop:disable ViewComponent/EncouragePreviewsForPrimer
        # @param button [Boolean] Whether the `summary` element should be styled as a button.
        # @param legacy_button_component [Boolean] Only applies when `button`=`true`.
        # Whether the `summary` element should use the legacy Primer::ButtonComponent or Primer::Beta::Button.
        # @param scheme [Symbol] Only applies when `button`=`true`.
        # <%= one_of(Primer::ButtonComponent::SCHEME_OPTIONS) %>
        # @param variant [Symbol] Only applies when `button`=`true`.
        # <%= one_of(Primer::ButtonComponent::VARIANT_OPTIONS) %>
        # @param disabled [Boolean] Whether the summary should be disabled or not.
        # @param caret [Boolean] Whether or not to render a caret. Only applicable when button=true.
        # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>
        def initialize(
          button: true,
          legacy_button_component: true,
          scheme: :default,
          variant: :small,
          disabled: false,
          caret: true,
          **system_arguments
        )
          @button = button
          @legacy_button_component = legacy_button_component
          @scheme = scheme
          @variant = variant
          @caret = caret
          @system_arguments = system_arguments
          @system_arguments[:tag] = :summary
          @system_arguments[:role] = "button"
          @system_arguments[:classes] = class_names(
            @system_arguments[:classes],
            "disabled" => disabled,
          )
        end

        def call
          render(component) do |component|
            component.with_trailing_action_icon(icon: "triangle-down") if !@legacy_button_component && @caret

            content
          end
        end

        private

        def component
          if !@button
            Primer::BaseComponent.new(**@system_arguments)
          elsif @legacy_button_component
            Primer::ButtonComponent.new(  # rubocop:disable Primer/DeprecatedComponents
              scheme: @scheme,
              variant: @variant,
              dropdown: @caret,
              **@system_arguments
            )
          else
            Primer::Beta::Button.new(
              scheme: @scheme,
              size: @variant,
              **@system_arguments
            )
          end
        end
      end
    end
  end
end
