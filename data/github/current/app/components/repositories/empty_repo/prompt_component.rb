# typed: strict
# frozen_string_literal: true

module Repositories
  module EmptyRepo
    class PromptComponent < ApplicationComponent
      include ApplicationComponent::Rescuable

      rescue_from StandardError, with: :nothing

      sig { returns T::Hash[Symbol, T.untyped] }
      attr_reader :system_arguments

      sig { returns String }
      attr_reader :title

      sig { returns String }
      attr_reader :description

      sig { returns Symbol }
      attr_reader :icon

      sig do
        params(
          title: String,
          description: String,
          icon: Symbol,
          system_arguments: Primer::SystemArgumentsValue
        ).void
      end
      def initialize(title:, description:, icon:, **system_arguments)
        @title = title
        @description = description
        @icon = icon
        @system_arguments = system_arguments
        @system_arguments[:mb] = [4, nil, 0, nil, nil] unless @system_arguments.key?(:mb)
        @system_arguments[:col] = [nil, nil, 6, nil, nil] unless @system_arguments.key?(:col)
      end

      renders_one :action,  types: {
        button: Primer::Beta::Button,
        raf: Organizations::MemberRequests::FeatureRequestComponent,
      }
    end
  end
end
