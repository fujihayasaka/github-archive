# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Updatable
      include Platform::Interfaces::Base
      include GitHub::ResilienceMixin
      description "Entities that can be updated."

      field :viewer_can_update, Boolean, description: "Check if the current viewer can update this object.", null: false

      def viewer_can_update
        with_async_database_error_fallback(
          @object.async_viewer_can_update?(@context[:viewer]),
          fallback: -> { raise Platform::Errors::ServiceUnavailable, "Viewer update permissions are currently unavailable." }
        )
      end
    end
  end
end
