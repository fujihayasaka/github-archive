# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module UserError
      include Platform::Interfaces::Base
      description "Represents an input error in mutations."

      # Let's kick the tires on this system a bit more before we go public with it.
      # For progress, see https://github.com/github/ecosystem-api/issues/1176
      visibility :under_development

      field :path, [String], description: "Path to the argument that caused the error. Nested arguments will be represented as an array where each item in the array is one level deeper in the path.", null: true

      field :message, String, description: "The reason this input field is problematic.", null: false

      field :short_message, String, visibility: :internal, description: "The reason this input field is problematic without the subject's name. This is only used to power the REST API.", null: false

      field :attribute, String, visibility: :internal, description: "The name of the legacy attribute that caused this error. This is only used to power the REST API.", null: false

      # There's currently only one implementer of this interface.
      # In the future, we can use more robust objects for this.
      def self.resolve_type(obj, ctx)
        Objects::ValidationError
      end
    end
  end
end
