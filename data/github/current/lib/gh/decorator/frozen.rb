# typed: strict
# frozen_string_literal: true

module GH
  module Decorator
    module Frozen
      extend GH::Decorator

      sig { override.params(decorable: GH::Decorator::Decorable, method_name: Symbol).void }
      def self.decorate_method(decorable, method_name)
        decorate(decorable, method_name) do |*args, **kwargs, &block|
          GH::Decorator::Frozen.deep_freeze(super(*args, **kwargs, &block))
        end
      end

      sig { params(object: Object).returns(Object) }
      def self.deep_freeze(object)
        object.each { |v| deep_freeze(v) } if object.is_a?(Enumerable)
        object.freeze
      end
    end
  end
end
