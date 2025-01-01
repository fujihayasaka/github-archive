# typed: strict
# frozen_string_literal: true

module GH
  module Domain
    class Cache
      module Cachable
        module Dirtyable
          extend ActiveSupport::Concern
          extend T::Helpers

          include Cachable

          abstract!

          included do
            T.bind(self, T.class_of(ActiveRecord::Base))
            after_commit(on: [:update, :destroy, :create]) do
              next unless GH::Context.enabled?

              cachable = T.cast(self, Cachable)
              cachable.domain.cache.dirty(cachable:)
            end
          end

          # As ActiveRecord instances are commonly mutated, sharing them across the scope of a request could
          # lead to troublesome bugs. Ensure a new instance is returned to the caller.
          sig { override.returns(Cachable) }
          def duplicate
            model = T.cast(self, ActiveRecord::Base)
            model.class.instantiate(model.attributes)
          end
        end
      end
    end
  end
end
