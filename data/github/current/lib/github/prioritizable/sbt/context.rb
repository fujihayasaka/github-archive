# typed: strict
# frozen_string_literal: true

module GitHub
  module Prioritizable
    module SBT
      # This is an abstract interface that can be included in an `ActiveRecord` model in order to define a container
      # within which an association can be kept in user-defined order.
      #
      # For example, in the Projects product, we allow users to drag and drop project items into priority order.
      # The way you would use this class for that use-case is illustrated below.
      #
      # This class assumes that the association that we are ordering implements the `GitHub::Prioritizable::SBT::Item`
      # interface.
      #
      # USAGE:
      #
      #   class Project
      #     # Declares this class as a container for user-ordered items.
      #     include GitHub::Prioritizable::SBT::Context
      #
      #     # This is the association on which we want to allow ordering.
      #     # The model that backs this must implement the `GitHub::Prioritizable::SBT::Item` interface.
      #     has_many :items
      #   end
      #
      #   class Item
      #     # Declare this class as the model that backs an item that we keep in user-defined order.
      #     include GitHub::Prioritizable::SBT::Item
      #
      #     belongs_to :project
      #   end
      #
      #   project = Project.find(1)
      #   item = project.items.first
      #
      #   # Place the item at the top of the prioritized list.
      #   project.prioritize!(item:, association: :items, position: Position::Top.new)
      #
      #   # Retrieve items in prioritized order. Given the statement above, `item` will be first in the array.
      #   project.prioritized_scope.all
      module Context
        autoload :PendingPriorityUpdate, "github/prioritizable/sbt/context/pending_priority_update"

        extend T::Helpers
        include Kernel

        requires_ancestor { ApplicationRecord::Base }
        requires_ancestor { GitHub::FlipperActor }

        abstract!

        class LockedForRebalance < StandardError; end

        # When either the numerator or denominator of the rational priority exceeds this value, then we trigger an
        # async rebalance. This makes sure that we don't accidentally get the same `virtual_priority` (float) value
        # from two different rational numbers.
        REBALANCE_THRESHOLD = 10_000_000
        METRIC_PREFIX = "github.prioritizable.sbt.context"

        # Asynchronously rebalances the priority values used in this context.
        #
        # We expect the implementation of this method to be shared with that of the existing `Prioritizable::Context`
        # module. This is useful while we are dual-writing to two different priority systems, but this is a temporary
        # bridge that will be removed in the future in favour of a dedicated interface.
        #
        # @param association The name of the `ActiveRecord` association that we want to rebalance.
        # @param actor_id The ID of the user who triggered this rebalance (if any).
        # @param perform_dual_writes Whether or not to write to both priority systems (this one and the legacy one).
        sig { abstract.params(association: Symbol, actor_id: Integer).void }
        def rebalance(association:, actor_id: GitHub.context[:actor_id]); end

        # Reports whether or not a rebalance is in progress.
        #
        # Similarly to `rebalance` we expect the implementation of this method to be shared with that of the existing
        # `Prioritizable::Context` module for now, but for us to implement this directly when we address
        # https://github.com/github/projects-platform/issues/1187.
        #
        # @param association The name of the `ActiveRecord` association that we might be rebalancing.
        sig { abstract.params(association: Symbol).returns(T::Boolean) }
        def locked_for_rebalance?(association:); end

        # Updates the priority of the given item.
        #
        # @param item The Item whose priority we should update
        # @param association The name of the `ActiveRecord` association to which the given item belongs.
        # @param position The desired new location of the given item
        #
        # @returns True if item was successfully updated. Otherwise, raises an exception.
        sig { params(item: Item, association: Symbol, position: Position).returns(T::Boolean) }
        def prioritize!(item:, association:, position: Position::Top.new)
          GitHub.dogstats.distribution_time("#{METRIC_PREFIX}.prioritize-bang", tags: metric_tags(association, position)) do
            raise LockedForRebalance if locked_for_rebalance?(association:)

            self.class.transaction do
              pending_update = PendingPriorityUpdate.new(
                context: self,
                association:, item:,
                position:,
                with_locking_reads: true
              )
              pending_update.apply
              item.save! # domain-isolation-query-violation:ignore:packages/issues (SELECT)
            end
          end
        end

        # Returns the new priority value that should be given to an item.
        #
        # This method is used to group together database updates when implementing dual writes to both this and the
        # legacy priority system. The value returned from this method may be nil if we should not in fact apply dual
        # writes when this method is called.
        #
        # @param item The Item whose priority we should update
        # @param association The name of the `ActiveRecord` association to which the given item belongs.
        # @param feature_flag An optional feature flag that we will check before returning a non-nil result.
        # @param position The desired new location of the given item
        #
        # @returns The write that we should apply to the database in order to update the item's priority correctly.
        #   This will be nil if the provided feature flag is not enabled for this context, or if we have not yet
        #   initially set all the new priority values for this context.
        sig do
          params(item: Item, association: Symbol, feature_flag: T.nilable(Symbol), position: Position)
          .returns(T.nilable(PendingPriorityUpdate))
        end
        def prioritize(item:, association:, feature_flag: nil, position: Position::Top.new)
          GitHub.dogstats.distribution_time("#{METRIC_PREFIX}.prioritize", tags: metric_tags(association, position)) do
            next if feature_flag && !self.feature_enabled?(feature_flag, memoize: false)
            next if has_unprioritized_items?(association)

            PendingPriorityUpdate.new(
              context: self,
              association:,
              item:,
              position:,
            )
          end
        end

        # Returns the given association in prioritized order (highest priority first).
        #
        # @param association The name of the `ActiveRecord` association to return in sorted order.
        #
        # @returns a sorted ActiveRecord::Relation
        sig { overridable.params(association: Symbol).returns(ActiveRecord::Relation) }
        def prioritized_scope(association)
          public_send(association).order(virtual_priority: :desc)
        end

        # Whether or not any items in this context have not yet been assigned a priority value.
        #
        # If this is true, then we need to rebalance this context.
        #
        # @param association The name of the `ActiveRecord` association to check for priority values.
        sig { params(association: Symbol).returns(T::Boolean) }
        def has_unprioritized_items?(association)
          public_send(association).exists?(virtual_priority: nil)
        end

        sig { params(kwargs: T.nilable(T.any(Item, Symbol, Position))).returns(T::Hash[String, T.untyped]) }
        def prioritize_trace_tags(**kwargs)
          {
            "context" => self.class.name,
            "association" => T.unsafe(kwargs[:association]).to_s,
            "position" => kwargs[:position] && T.unsafe(kwargs[:position]).class.name.demodulize.downcase,
          }.compact
        end

        sig { params(association: Symbol, position: Position).returns(T::Array[String]) }
        private def metric_tags(association, position)
          [
            "context:#{self.class.name}",
            "association:#{association}",
            "position:#{T.unsafe(position).class.name.demodulize.downcase}"
          ]
        end
      end
    end
  end
end
