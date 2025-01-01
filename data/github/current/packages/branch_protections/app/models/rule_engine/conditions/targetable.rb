# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Conditions
    module Targetable
      extend T::Helpers
      include GitHub::Memoizer

      requires_ancestor { Object }

      # A set of attributes that can be targeted by conditions
      class Attribute < T::Enum
        enums do
          RefName = new("ref_name")
          Repository = new("repository")
          RepositoryGlobalId = new("repository_global_id")
          RepositoryName = new("repository_name")
          RepositoryCustomProperties = new("repository_custom_properties")
          RepositorySystemProperties = new("repository_system_properties")
          OrganizationCustomProperties = new("organization_custom_properties")
          Organization = new("organization")
          Enterprise = new("enterprise")
          User = new("user")
        end
      end

      abstract!

      # Returns a hash of attributes that can be targeted by conditions
      # Attributes returned here should not include attributes defined by the parent
      sig { abstract.returns(T::Hash[Attribute, T.untyped]) }
      def targetable_attributes; end

      # Returns a promise for the parent of this targetable object
      # A parent's attributes are also accessible to conditions
      sig { abstract.returns(Promise[T.nilable(Targetable)]) }
      def async_targetable_parent; end

      sig { returns(Promise[T.nilable(Targetable)]) }
      memoize def async_memoized_targetable_parent
        async_targetable_parent
      end

      # Returns the value of the attribute for this targetable object
      # This method will recursively check the parent of this object if the attribute is not defined at this level
      sig { params(attribute: Attribute).returns(T.untyped) }
      def get_attribute(attribute)
        attribute_value = if targetable_attributes.key?(attribute)
          targetable_attributes[attribute]
        else
          async_memoized_targetable_parent.sync&.get_attribute(attribute)
        end

        if attribute_value.is_a?(Proc)
          @memoized_attributes ||= T.let({}, T.nilable(T::Hash[Attribute, T.untyped]))
          @memoized_attributes[attribute] ||= begin
            attribute_value.call
          end
        else
          attribute_value
        end
      end

      sig { params(targets: T::Array[Targetable]).void }
      def self.recursive_prefill_parents(targets)
        Promise.all(targets.map(&:async_memoized_targetable_parent)).then do |parents|
          if parents.compact.any?
            recursive_prefill_parents(parents.compact)
          end
        end
      end
    end
  end
end
