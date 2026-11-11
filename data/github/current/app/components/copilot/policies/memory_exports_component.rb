# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class MemoryExportsComponent < ApplicationComponent
      sig { params(entity_name: String, entity_type: String).void }
      def initialize(entity_name:, entity_type: "enterprise")
        @entity_name = T.let(entity_name, String)
        @entity_type = T.let(entity_type, String)
        @dialog_id = T.let("copilot-memory-exports-confirmation", String)
      end

      sig { returns(T::Boolean) }
      def render?
        logged_in?
      end

      sig { returns(String) }
      attr_reader :entity_name

      sig { returns(String) }
      attr_reader :entity_type

      sig { returns(String) }
      attr_reader :dialog_id

      sig { returns(String) }
      def confirmation_text
        "By clicking Download memories, you confirm you have permission " \
          "to access this information on behalf of users in this #{entity_type}."
      end
    end
  end
end
