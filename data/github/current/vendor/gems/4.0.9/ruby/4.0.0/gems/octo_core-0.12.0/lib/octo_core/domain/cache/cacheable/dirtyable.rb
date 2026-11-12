# typed: strict
# frozen_string_literal: true

module OctoCore
  module Domain
    class Cache
      module Cacheable
        module Dirtyable
          extend T::Sig
          extend T::Helpers

          include Cacheable

          abstract!

          sig { params(base: T.untyped).void }
          def self.included(base)
            T.bind(self, T.class_of(ActiveRecord::Base))
            after_commit(on: [:update, :destroy, :create]) do
              next unless OctoCore::Context.enabled?

              cacheable = T.cast(self, Cacheable)
              cacheable.domain.cache.dirty(cacheable:)
            end
          end

          # As ActiveRecord instances are commonly mutated, sharing them across the scope of a request could
          # lead to troublesome bugs. Ensure a new instance is returned to the caller.
          sig { override.returns(Cacheable) }
          def duplicate
            model = T.cast(self, ActiveRecord::Base)
            model.class.instantiate(model.attributes)
          end
        end
      end
    end
  end
end
