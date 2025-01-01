# typed: strict
# frozen_string_literal: true

require_relative "decorator/caller_attribution"
require_relative "decorator/decorable"
require_relative "decorator/id_caching"
require_relative "decorator/memoization"
require_relative "decorator/test_bed_id_caching"
require_relative "decorator/test_bed_memoization"
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
  end
end
