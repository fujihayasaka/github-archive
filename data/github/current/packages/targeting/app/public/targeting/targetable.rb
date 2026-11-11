# typed: strict
# frozen_string_literal: true

module Targeting
  module Targetable
    extend T::Helpers
    include GitHub::Memoizer

    abstract!

    # Returns a hash of attributes that can be targeted by conditions
    # Attributes returned here should not include attributes defined by the parent
    sig { abstract.returns(T::Hash[Attribute, T.untyped]) }
    def targetable_attributes; end

    # Returns a promise for the parent of this targetable object
    # A parent's attributes are also accessible to conditions
    sig { abstract.returns(Promise[T::Array[Targeting::Targetable]]) }
    def async_targetable_parents; end

    sig { returns(Promise[T::Array[Targeting::Targetable]]) }
    memoize def async_memoized_targetable_parents
      async_targetable_parents
    end

    # Returns the value of the attribute for this targetable object
    # This method will recursively check the parent of this object if the attribute is not defined at this level
    sig { params(attribute: Attribute).returns(T.untyped) }
    def get_attribute(attribute)
      attribute_value = if targetable_attributes.key?(attribute)
        targetable_attributes[attribute]
      else
        async_memoized_targetable_parents.sync.find { |parent| parent.get_attribute(attribute) }&.get_attribute(attribute)
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

    sig { params(attribute: Attribute).returns(T::Array[T.untyped]) }
    def get_all_attributes(attribute)
      attribute_values = if targetable_attributes.key?(attribute)
        [targetable_attributes[attribute]]
      else
        async_memoized_targetable_parents.sync.map { |parent| parent.get_all_attributes(attribute) }.compact.flatten
      end

      attribute_values.map do |attribute_value|
        if attribute_value.is_a?(Proc)
          @memoized_attributes ||= T.let({}, T.nilable(T::Hash[Attribute, T.untyped]))
          @memoized_attributes[attribute] ||= begin
            attribute_value.call
          end
        else
          attribute_value
        end
      end
    end

    # Long-term, the goal is to have Targetable be a mixin that can be applied to any class.
    # Until we move Targetable into a separate package, we use Targets:* classes to wrap the actual records.
    # This method should return the actual record that this Targetable represents.
    sig { overridable.returns(T.untyped) }
    def internal_record
      self
    end

    # This method must exist on Targetable. However, requiring Kernel currently breaks
    # the Copilot::* SimpleDelegator users of this class. Ideally we can fix that
    # but this is a temporary workaround.
    sig { params(arg0: T::Module[T.anything]).returns(T::Boolean) }
    def is_a?(arg0)
      super
    end

    sig { params(targets: T::Array[Targeting::Targetable]).void }
    def self.recursive_prefill_parents(targets)
      Promise.all(targets.map(&:async_memoized_targetable_parents)).then do |parents|
        if (valid_parents = parents.flatten.compact).any?
          recursive_prefill_parents(valid_parents)
        end
      end
    end
  end
end
