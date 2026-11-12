# typed: strict
# frozen_string_literal: true

module OctoCore
  module Decorator
    # Any class or module wishing to be decorated must extend this module. The class method `decorate_with` can then
    # be called to add decorators to the class. `apply_decorators!` must be called for the decorators to have any
    # effect. It is idempotent and can be called in the constructor if needed. Once `apply_decorators!` has been
    # called, no additional decorators can be added to the module.
    module Decorable
      extend T::Sig
      extend T::Helpers

      requires_ancestor { Module }

      sig { returns(T::Hash[Decorator, T::Array[Symbol]]) }
      def __octo_decorators
        return T.must(@__octo_decorators) if defined?(@__octo_decorators)

        decorators = {}
        if respond_to?(:superclass)
          T.bind(self, T::Class[T.anything])
          if superclass.respond_to?(:__octo_decorators)
            decorators = T.cast(superclass, Decorable).__octo_decorators.dup

            # deep dup the method name list
            decorators.keys.each do |k|
              decorators[k] = T.must(decorators[k]).dup
            end
          end
        end

        @__octo_decorators = T.let(decorators, T.nilable(T::Hash[Decorator, T::Array[Symbol]]))
        T.must(@__octo_decorators)
      end

      sig { returns(T::Hash[Decorator, T::Module[T.anything]]) }
      def __octo_decorator_modules
        return T.must(@__octo_decorator_modules) if defined?(@__octo_decorator_modules)

        @__octo_decorator_modules = T.let({}, T.nilable(T::Hash[Decorator, T::Module[T.anything]]))
        T.must(@__octo_decorator_modules)
      end

      # Apply the decorator to the current decorable class. Only decorate the given methods,
      # or all instance methods if none specified.
      sig { params(decorator: Decorator, only: T::Array[Symbol]).void }
      def decorate_with(decorator, only: [])
        __octo_decorators[decorator] = only.dup
      end

      sig { void }
      def apply_decorators!
        return if defined?(@__octo_decorated) && T.must(@__octo_decorated)

        all_methods = public_instance_methods(true) - Object.public_instance_methods
        __octo_decorators.each do |decorator, only_methods|
          methods = if only_methods.any?
                      missing_methods = only_methods - all_methods
                      raise "Trying to decorate methods that don't exist: #{missing_methods.join(", ")}" if missing_methods.any?
                      only_methods
          else
            all_methods
          end

          methods.each do |method_name|
            decorator.decorate_method(self, method_name)
          end
        end

        @__octo_decorated = T.let(true, T.nilable(T::Boolean))
      end
    end
  end
end
