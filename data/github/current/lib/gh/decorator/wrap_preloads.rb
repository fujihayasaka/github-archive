# typed: strict
# frozen_string_literal: true

module GH
  module Decorator
    module WrapPreloads
      extend GH::Decorator

      sig { override.params(decorable: GH::Decorator::Decorable, method_name: Symbol).void }
      def self.decorate_method(decorable, method_name)
        decorate(decorable, method_name) do |*args, **kwargs, &block|
          result = super(*args, **kwargs, &block)
          Prelude.wrap(result) if result.is_a?(Enumerable) && result.first.respond_to?(:prelude_preloader=)
          result
        end
      end
    end
  end
end
