# typed: strict
# frozen_string_literal: true

module GitHub
  # Interface for ActiveRecord models whose background destroy/delete operations
  # should be routed through a domain. Include this module and implement the
  # `.domain` class method to return a domain that includes
  # GH::Domain::DestroyMethods. An instance `#domain` method is provided that
  # delegates to the class method.
  #
  # Models using `destroy_in_background_with ..., use_domain: true` or
  # `delete_in_background_with ..., use_domain: true` must include this module.
  # A DSL-level check verifies the module is included when `use_domain: true`
  # is specified.
  #
  # Example:
  #   class Widget < ApplicationRecord::Base
  #     include GitHub::DomainDestroyableModel
  #     destroy_in_background_with :parent, use_domain: true
  #
  #     sig { override.returns(T.all(GH::Domain::Base, GH::Domain::DestroyMethods)) }
  #     def self.domain
  #       Widgets.domain
  #     end
  #   end
  module DomainDestroyableModel
    extend T::Helpers
    requires_ancestor { Object }
    abstract!

    sig { overridable.returns(T.all(GH::Domain::Base, GH::Domain::DestroyMethods)) }
    def domain
      T.unsafe(self.class).domain
    end

    module ClassMethods
      extend T::Helpers
      interface!

      sig { abstract.returns(T.all(GH::Domain::Base, GH::Domain::DestroyMethods)) }
      def domain; end
    end

    mixes_in_class_methods(ClassMethods)
  end
end
