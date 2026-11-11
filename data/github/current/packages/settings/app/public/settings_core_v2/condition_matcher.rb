# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  class ConditionMatcher
    extend T::Helpers

    abstract!

    # The targeting attribute this matcher handles (e.g., "repository.name")
    sig { abstract.returns(String) }
    def attribute; end

    # The effective value of this attribute for a given resource
    # Returns nil if the attribute is not applicable to the resource or value cannot be determined
    sig { abstract.params(resource: T.untyped, sub_type: T.nilable(String)).returns(T.nilable(String)) }
    def effective_value(resource, sub_type = nil); end

    # Count how many child resources of the given parent match the condition.
    # Returns {count: matched, total: all_children}
    sig { abstract.params(parent: T.untyped, operation: IConditionExpression::Operation, value: T.any(String, T::Array[String]), sub_type: T.nilable(String)).returns({ count: Integer, total: Integer }) }
    def count_matches(parent, operation, value, sub_type = nil); end

    # Search for matching values for this attribute. Used by the metadata API
    # to power autocomplete/search in the targeting UI.
    # Returns an array results.
    sig { overridable.params(parent: T.untyped, query: T.nilable(String), limit: Integer).returns(T.untyped) }
    def search(parent, query, limit: 20)
      []
    end

    # Resolve an array of IDs to their corresponding resources, scoped to the given parent.
    sig { overridable.params(parent: T.untyped, ids: T::Array[String]).returns(T.untyped) }
    def resolve(parent, ids)
      []
    end

    # Returns available metadata for this attribute (e.g., property definitions).
    # Used by the metadata API to populate select dropdowns in the targeting UI.
    sig { overridable.params(parent: T.untyped).returns(T.nilable(T::Array[T::Hash[String, T.untyped]])) }
    def metadata(parent)
      nil
    end
  end
end
