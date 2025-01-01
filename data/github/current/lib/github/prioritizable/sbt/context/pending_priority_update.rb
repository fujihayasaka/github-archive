# typed: strict
# frozen_string_literal: true

module GitHub
  module Prioritizable
    module SBT
      module Context
        # This class represents an unapplied database update for a priority value computed with the
        # `GitHub::Prioritizable::Context` class.
        #
        # USAGE:
        #
        #   # Build an update without making any changes to the item.
        #   pending = PendingPriorityUpdate.new(context:, association:, item:, :position)
        #
        #   # Change the item's `rational_priority` value only in memory
        #   pending.apply
        #
        #   # Persist the new `rational_priority` value to the database
        #   item.save!
        #
        class PendingPriorityUpdate < T::Struct
          extend T::Sig

          const :context, Context
          const :association, Symbol
          const :item, Item
          const :position, Position
          const :with_locking_reads, T::Boolean, default: false

          # Updates the rational priority of the given item without saving it.
          sig { void }
          def apply
            item.rational_priority = compute_new_priority
          end

          sig { returns(Rational) }
          private def compute_new_priority
            tree = SternBrocotTree.new

            # Sorbet needs a variable rather than a method call to infer types in a case statement, so declare a
            # variable rather than using the `position` accessor directly.
            pos = position

            result = case pos
            when Position::HigherThan
              tree.infer_intermediate(
                # Use the item from the position as the lower bound so we get a higher priority value
                lower_bound: pos.item.rational_priority.to_r,
                upper_bound: least_higher_priority(pos.item)
              )
            when Position::LowerThan
              tree.infer_intermediate(
                # Use the item from the position as the upper bound so we get a lower priority value
                lower_bound: greatest_lower_priority(pos.item).to_r,
                upper_bound: pos.item.rational_priority,
              )
            when Position::Top
              tree.infer_intermediate(lower_bound: highest_priority.to_r)
            when Position::Bottom
              tree.infer_intermediate(upper_bound: lowest_priority)
            else
              T.absurd(pos)
            end

            if result.numerator > REBALANCE_THRESHOLD || result.denominator > REBALANCE_THRESHOLD
              GitHub.logger.info(
                "context": context.class.name,
                "context.id": context.id,
                "message": "project rebalance triggered by rebalance threshold",
                "code.namespace": self.class.name,
                "code.function": "new_priority",
                "gh.prioritizable.sbt.new_priority.item.id": item.id,
                "gh.prioritizable.sbt.new_priority.association": association,
                "gh.prioritizable.sbt.new_priority.position": pos.class.name,
              )
              context.rebalance(association:)
            end

            result
          end

          sig { params(item: Item).returns(T.nilable(Rational)) }
          private def least_higher_priority(item)
            first_priority_value(
              context
                .public_send(association)
                .where("virtual_priority > ?", T.unsafe(item).virtual_priority)
                .order(:virtual_priority)
            )
          end

          sig { params(item: Item).returns(T.nilable(Rational)) }
          private def greatest_lower_priority(item)
            first_priority_value(
              context
                .public_send(association)
                .where("virtual_priority < ?", T.unsafe(item).virtual_priority)
                .order(virtual_priority: :desc)
            )
          end

          sig { returns(T.nilable(Rational)) }
          private def highest_priority
            first_priority_value(context.public_send(association).order(virtual_priority: :desc))
          end

          sig { returns(T.nilable(Rational)) }
          private def lowest_priority
            first_priority_value(context.public_send(association).order(:virtual_priority))
          end

          sig { params(scope: ActiveRecord::Relation).returns(T.nilable(Rational)) }
          private def first_priority_value(scope)
            scope = scope.lock if with_locking_reads
            scope.limit(1).first&.rational_priority
          end
        end
      end
    end
  end
end
