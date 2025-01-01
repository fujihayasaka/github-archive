# typed: true
# frozen_string_literal: true

module SecretScanning
  module CustomPatterns
    class RemovePatternsBulkComponent < ApplicationComponent

      def initialize(scope:)
        @scope = scope
      end

      def delete_confirmation_scope_text
        return "this repository" if @scope == :repo

        "all repositories with GitHub Advanced Security enabled"
      end


    end
  end
end
