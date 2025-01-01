# typed: true
# frozen_string_literal: true

module Pages
  module BuildTypes
    class SelectComponent < ApplicationComponent

      attr_reader :current_build_type

      def initialize(repository:)
        @repository = repository
        @current_build_type = repository.page&.build_type&.to_sym || :legacy
      end

      def workflow?
        current_build_type == :workflow
      end

      def legacy?
        current_build_type == :legacy
      end

      def actions_disabled?
        @repository.actions_disabled?
      end

      def archived?
        @repository.archived?
      end

    end
  end
end
