# typed: strict
# frozen_string_literal: true

require_relative "decorator/caller_attribution"
require_relative "decorator/frozen"
require_relative "decorator/mysql_instrumentation"
require_relative "decorator/package_context"
require_relative "decorator/tracing"
require_relative "decorator/wrap_preloads"

module GH
  # Decorators allow us to add behavior to the methods of a class without modifying the class itself. This is
  # accomplished by creating anonymous modules to contain the method decorations which are then prepended to the
  # class' ancestor list.
  #
  # Extend this module to create a new decorator. Decorators must implement the `decorate_method` method.
  # The implementation must call `decorate` at least once to actually have any effect on the decorable. The block
  # passed to the `decorate` method must call `super` and pass in the arguments of the block unless you want the
  # decorator to prevent execution of the decorated method entirely.
  module Decorator
    extend T::Helpers
    include Kernel

    abstract!

    sig do
      abstract.params(decorable: Decorable, method_name: Symbol).void
    end
    def decorate_method(decorable, method_name); end

    # Called from the implementation's decorate_method method to actually add the decorator to the decorable's
    # anonymous module.
    sig do
      params(
        decorable: Decorable,
        method_name: Symbol,
        decorator_block: T.proc.params(arg0: T.untyped, arg1: T.untyped, blk: T.proc.void).void
      ).void
    end
    def decorate(decorable, method_name, &decorator_block)
      mod = decorable.__gh_decorator_modules[self]
      if mod.nil?
        mod = Module.new
        decorable.prepend(mod)
        decorable.__gh_decorator_modules[self] = mod
      end

      mod.define_method(method_name, decorator_block)
    end

    # Any class or module wishing to be decorated must extend this module. The class method `decorate_with` can then
    # be called to add decorators to the class. `apply_decorators!` must be called for the decorators to have any
    # effect. It is idempotent and can be called in the constructor if needed. Once `apply_decorators!` has been
    # called, no additional decorators can be added to the module.
    module Decorable
      extend T::Helpers

      requires_ancestor { Module }

      sig { returns(T::Hash[Decorator, T::Array[Symbol]]) }
      def __gh_decorators
        return T.must(@__gh_decorators) if defined?(@__gh_decorators)

        decorators = {}
        if respond_to?(:superclass)
          T.bind(self, T::Class[T.anything])
          if superclass.respond_to?(:__gh_decorators)
            decorators = T.cast(superclass, Decorable).__gh_decorators.dup

            # deep dup the method name list
            decorators.keys.each do |k|
              decorators[k] = T.must(decorators[k]).dup
            end
          end
        end

        @__gh_decorators = T.let(decorators, T.nilable(T::Hash[Decorator, T::Array[Symbol]]))
        T.must(@__gh_decorators)
      end

      sig { returns(T::Hash[Decorator, Module]) }
      def __gh_decorator_modules
        return T.must(@__gh_decorator_modules) if defined?(@__gh_decorator_modules)

        @__gh_decorator_modules = T.let({}, T.nilable(T::Hash[Decorator, Module]))
        T.must(@__gh_decorator_modules)
      end

      # Apply the decorator to the current decorable class. Only decorate the given methods,
      # or all instance methods if none specified.
      sig { params(decorator: Decorator, only: T::Array[Symbol]).void }
      def decorate_with(decorator, only: [])
        __gh_decorators[decorator] = only.dup
      end

      @@skip_decorables = T.let(nil, T.nilable(T::Array[Symbol]))
      cattr_reader :skip_decorables

      sig { params(method_names: Symbol).void }
      def skip_decoration(*method_names)
        raise ArgumentError, "invalid skip_decoration method names: #{method_names}" unless (public_instance_methods(false) - method_names).empty?

        @@skip_decorables ||= []
        @@skip_decorables.concat(method_names)
      end

      sig { void }
      def apply_decorators!
        return if defined?(@__gh_decorated) && T.must(@__gh_decorated)

        all_methods = public_instance_methods(true) - GH::Domain::Base.public_instance_methods(true)
        all_methods -= skip_decorables if skip_decorables
        __gh_decorators.each do |decorator, only_methods|
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

        @__gh_decorated = T.let(true, T.nilable(T::Boolean))
      end
    end
  end
end
