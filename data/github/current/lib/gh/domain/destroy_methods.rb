# typed: strict
# frozen_string_literal: true

module GH
  module Domain
    # Interface for domain classes that handle background destruction/deletion
    # of records. Include this in a Domain class alongside GH::Domain::Base to
    # enable routing background dependent deletes through the domain layer.
    #
    # Example:
    #   class Widgets::Domain < GH::Domain::Base
    #     include GH::Domain::DestroyMethods
    #
    #     sig { override.params(record: ActiveRecord::Base).returns(T::Boolean) }
    #     def background_destroy(record)
    #       record.destroy
    #     end
    #
    #     sig { override.params(ids: T::Array[T.any(Integer, String)]).returns(Integer) }
    #     def background_delete(ids)
    #       Widget.where(id: ids).delete_all
    #     end
    #   end
    module DestroyMethods
      extend T::Helpers

      interface!
      requires_ancestor { GH::Domain::Base }

      # Destroy a single record through the domain layer, firing callbacks.
      # Called by DestroyDependentRecordsJob when use_domain is enabled.
      sig { abstract.params(record: ActiveRecord::Base).returns(T::Boolean) }
      def background_destroy(record); end

      # Delete records by ID through the domain layer, bypassing callbacks.
      # Called by DeleteDependentRecordsJob when use_domain is enabled.
      sig { abstract.params(ids: T::Array[T.any(Integer, String)]).returns(Integer) }
      def background_delete(ids); end
    end
  end
end
