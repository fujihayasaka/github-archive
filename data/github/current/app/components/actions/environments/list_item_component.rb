# typed: true
# frozen_string_literal: true

module Actions
  module Environments
    class ListItemComponent < ApplicationComponent
      attr_reader :environment

      def initialize(environment:, num_secrets:, edit_path:, delete_path:, num_variables:)
        @environment = environment
        @num_secrets = num_secrets
        @num_variables = num_variables
        @edit_path = edit_path
        @delete_path = delete_path
      end

      def show_protection_rules?
        gates_size > 0
      end

      def show_secrets?
        @num_secrets > 0
      end

      def show_variables?
        @num_variables > 0
      end

      memoize def gates_size
        environment.gates.size
      end
    end
  end
end
