# typed: strict
# frozen_string_literal: true

module GH
  module Domain
    # Interface for domain classes that expose a batched `by_ids` reader so
    # they can be used as the load path for `Platform::Loaders::ActiveRecord`.
    # Include this in a Domain class alongside GH::Domain::Base to opt a
    # domain in as a load source for an ActiveRecord model that includes
    # GitHub::DomainLoadableModel.
    #
    # `by_ids` must accept an Array of integer ids and return any iterable
    # of records keyed by `:id`. Both `T::Array[ActiveRecord::Base]` and
    # `GH::Domain::Collection[...]` (which mixes in `Enumerable`) satisfy
    # this contract. The return type is declared as `T.untyped` because
    # sorbet-runtime's covariance check does not recognize Collection as
    # an Enumerable subtype, and constraining the return type would
    # exclude existing domain implementations such as
    # `Repositories::Domain#by_ids`. Each returned element must respond to
    # `[:id]` so the GraphQL loader can build its lookup map.
    #
    # Overrides may add optional keyword arguments (e.g. `allow_deleted:`,
    # `batch_size:`) with defaults; Sorbet allows extra optional kwargs in
    # an override. Required keyword arguments are not allowed because the
    # loader calls `by_ids(ids)` positionally.
    #
    # Example with only the required positional argument:
    #   class Widgets::Domain < GH::Domain::Base
    #     include GH::Domain::IdReaders
    #
    #     sig { override.params(ids: T::Array[Integer]).returns(T::Array[ActiveRecord::Base]) }
    #     def by_ids(ids)
    #       Widget.where(id: ids).to_a
    #     end
    #   end
    #
    # Example with additional optional kwargs (compatible with the loader):
    #   sig do
    #     override.params(
    #       ids: T::Array[Integer],
    #       allow_deleted: T::Boolean,
    #     ).returns(GH::Domain::Collection[IWidget])
    #   end
    #   def by_ids(ids, allow_deleted: false)
    #     ...
    #   end
    module IdReaders
      extend T::Helpers

      interface!
      requires_ancestor { GH::Domain::Base }

      sig { abstract.params(id: Integer).returns(T.untyped) }
      def by_id(id); end

      # Fetch records by primary id through the domain layer. Called by
      # Platform::Loaders::ActiveRecord when the requested model opts in via
      # GitHub::DomainLoadableModel. Order is not significant; the loader
      # rebuilds a lookup map keyed by `:id`.
      sig { abstract.params(ids: T::Array[Integer]).returns(T.untyped) }
      def by_ids(ids); end
    end
  end
end
