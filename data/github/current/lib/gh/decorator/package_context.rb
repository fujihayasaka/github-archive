# typed: strict
# frozen_string_literal: true

module GH
  module Decorator
    module PackageContext
      extend GH::Decorator

      sig { override.params(decorable: GH::Decorator::Decorable, method_name: Symbol).void }
      def self.decorate_method(decorable, method_name)
        decorate(decorable, method_name) do |*args, **kwargs, &block|
          GitHub::DomainIsolation.within_domain_of(self.class) { super(*args, **kwargs, &block) }
        end
      end
    end
  end
end
