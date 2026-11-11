# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      module RecordObjectAccess
        # Hook into GraphQL-Ruby's initialization to record
        # that we're touching this object
        def initialize(object, context)
          super
          # Accessed objects during _this_ query:
          add_if_unique(context[:query_tracker].accessed_objects, self)
          # Accessed objects during the whole HTTP request:
          add_if_unique(Platform::GlobalScope.accessed_objects, self)
        end

        private

        # Search `objects` for an entry equivalent to `new_object`.
        # If one is found, do nothing.
        # If one is _not_ found, add `new_object` to the list.
        def add_if_unique(objects, new_object)
          objects[[new_object.class, new_object.object]] ||= new_object
        end
      end
    end
  end
end
