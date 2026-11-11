# typed: strict
# frozen_string_literal: true

module GitHub
  # Interface for ActiveRecord models whose `Platform::Loaders::ActiveRecord`
  # `:id` loads should be routed through a domain. Include this module and
  # implement the `.domain` class method to return a domain that includes
  # GH::Domain::IdReaders. An instance `#domain` method is provided that
  # delegates to the class method.
  #
  # When a model opts in via this module, `Platform::Loaders::ActiveRecord`
  # will call `Model.domain.by_ids(ids)` instead of `Model.where(id: ids)`
  # when the loader is reading the model by `:id` from a bare class (no
  # relation scoping) and without an explicit `shard_key:`. This lets a
  # model centralize cache, telemetry, and read routing inside its domain
  # without per-model special cases in the loader.
  #
  # Example:
  #   class Widget < ApplicationRecord::Base
  #     include GitHub::DomainLoadableModel
  #
  #     sig { override.returns(T.all(GH::Domain::Base, GH::Domain::IdReaders)) }
  #     def self.domain
  #       Widgets.domain
  #     end
  #   end
  module DomainLoadableModel
    extend T::Helpers
    requires_ancestor { ApplicationRecord::Base }
    abstract!

    sig { params(base: T.class_of(ApplicationRecord::Base)).void }
    def self.included(base)
      super
      T.unsafe(base).domain_loadable = true
    end

    sig { overridable.returns(T.all(GH::Domain::Base, GH::Domain::IdReaders)) }
    def domain
      T.unsafe(self.class).domain
    end

    module ClassMethods
      extend T::Helpers
      abstract!

      sig { abstract.returns(T.all(GH::Domain::Base, GH::Domain::IdReaders)) }
      def domain; end
    end

    mixes_in_class_methods(ClassMethods)
  end
end
