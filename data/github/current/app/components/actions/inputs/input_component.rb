# typed: true
# frozen_string_literal: true

module Actions
  module Inputs
    class InputComponent < ApplicationComponent
      attr_reader :input, :counter

      def initialize(input:, input_counter:, current_repository:)
        @input = input
        @counter = input_counter
        @current_repository = current_repository
      end

      private

      def id
        "input_#{@counter}"
      end

      def input_component
        case @input[:type]
        when Actions::ParsedWorkflow::INPUT_TYPE_CHOICE
          Actions::Inputs::DropdownInputComponent.new(input: input, id: id)
        when Actions::ParsedWorkflow::INPUT_TYPE_ENVIRONMENT
          Actions::Inputs::EnvironmentInputComponent.new(input: input, id: id, current_repository: @current_repository)
        when Actions::ParsedWorkflow::INPUT_TYPE_BOOLEAN
          Actions::Inputs::BooleanInputComponent.new(input: input, id: id)
        when Actions::ParsedWorkflow::INPUT_TYPE_NUMBER
          if FeatureFlag.vexi.enabled_or_raise?(:actions_number_type_dispatch_inputs, @current_repository.owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
            Actions::Inputs::NumberInputComponent.new(input: input, id: id)
          else
            Actions::Inputs::TextInputComponent.new(input: input, id: id)
          end
        else
          Actions::Inputs::TextInputComponent.new(input: input, id: id)
        end
      end
    end
  end
end
