# typed: strict
# frozen_string_literal: true

module GitHub
  module Prioritizable
    extend T::Helpers
    autoload :SternBrocotTree, "github/prioritizable/stern_brocot_tree"
    autoload :SBT, "github/prioritizable/sbt"
    autoload :Context, "github/prioritizable/context"

    requires_ancestor { Kernel }
    requires_ancestor { ApplicationRecord::Base }

    extend T::Helpers
    include ActiveRecord::ConnectionAdapters::Quoting

    GAP_SIZE = 100
    MAXIMUM_PRIORITIZABLE_ITEM_COUNT = 2_500
    MAX_MOVES = 200
    MOVES_THRESHOLD_FOR_REBALANCE = T.let(MAX_MOVES / 2, Integer)

    # Two things here with this constant:
    #  1) This specific number is the MySQL BIGINT (unsigned) max value
    #  2) It's wrapped in a string first, to get around this error: https://sorbet.org/docs/error-reference#3002
    MAX_PRIORITY_VALUE = T.let("18446744073709551615".to_i, Integer)
    MAX_TRANSACTION_NESTING_LEVELS = T.let(0, Integer)
    START_VALUE = T.let(MAX_PRIORITY_VALUE / 2, Integer)

    sig { params(include_self: T::Boolean).returns(ActiveRecord::Relation) }
    def siblings(include_self: false)
      siblings = T.unsafe(context).send(self.class.context_reflection)
      if !include_self && persisted?
        siblings = siblings.where("#{self.class.quoted_table_name}.id <> ?", id)
      end
      siblings.where.not(priority: nil)
    end

    sig { returns(T::Boolean) }
    def prioritized?
      !!(persisted? && raw_priority && raw_priority != MAX_PRIORITY_VALUE)
    end

    sig { returns(T::Boolean) }
    def highest_priority?
      !siblings.where("priority > ?", raw_priority).exists?
    end

    sig do
      type_parameters(:E)
      .params(
        before: T.nilable(T.all(T.type_parameter(:E), ApplicationRecord::Base)),
        after: T.nilable(T.all(T.type_parameter(:E), ApplicationRecord::Base)),
        position: T.nilable(T.any(Integer, Symbol)),
        in_context: T.nilable(Context),
        association: T.nilable(Symbol),
        dual_write: T.nilable(SBT::Context::PendingPriorityUpdate)
      ).returns(T.untyped)
    end
    def reprioritize(before: nil, after: nil, position: nil, in_context: context, association: nil, dual_write: nil)
      # Disallow moving a record that's in a locked context.
      if context&.locked_for_rebalance?(association: association)
        raise GitHub::Prioritizable::Context::LockedForRebalance
      end

      if [before, after, position].compact.length > 1
        raise ConflictingPrioritizationArgumentError, "Must provide maximum one prioritization parameter"
      end

      if in_context != context
        # Disallow moving a record into a locked context.
        if T.unsafe(in_context).locked_for_rebalance?(association: association)
          raise GitHub::Prioritizable::Context::LockedForRebalance
        end

        reparent(in_context)
      end

      if before
        insert_before(before, association: association, dual_write:)
      elsif after
        insert_after(after, association: association, dual_write:)
      elsif position == :bottom
        insert_at_bottom(association: association, dual_write:)
      else
        insert_at_top(association: association, dual_write:)
      end
    rescue ActiveRecord::RecordNotUnique
      self.errors.add(:prioritization, "The priority you are attempting to set for this record is not unique")
      GitHub.dogstats.increment("#{kind}.prioritization.error.record_not_unique")
      T.cast(self, T.type_parameter(:E))
    rescue ActiveModel::RangeError
      # We should not end up in this state, as priorities should have been effectively rebalanced
      # But adding this as a safeguard to prevent 500s
      self.errors.add(:prioritization, "The priority you are attempting to set for this record is not valid")
      T.cast(self, T.type_parameter(:E))
    end

    # Internal: The logical priority (1, 2, 3, ...) value for this record.
    #
    # Returns an Integer
    sig { returns(T.nilable(Integer)) }
    def canonical_priority
      return unless persisted?
      siblings(include_self: true)
        .where("#{self.class.quoted_table_name}.#{safe_column(:priority)} >= ?", raw_priority)
        .count
    end

    sig { returns(T.nilable(Integer)) }
    def raw_priority
      read_attribute(:priority)
    end

    sig { returns(T.nilable(Integer)) }
    def context_id
      read_attribute(context_column)
    end

    private

    sig { returns(T::Boolean) }
    def subject_is_polymorphic?
      !!association(T.unsafe(self).priority_subject).reflection.options[:polymorphic]
    end

    sig { returns(Symbol) }
    def subject_type_column
      association(T.unsafe(self).priority_subject).reflection.foreign_type
    end

    sig { returns(Symbol) }
    def subject_type
      read_attribute(subject_type_column)
    end

    sig { returns(T.any(Symbol, String)) }
    def subject_id_column
      association(T.unsafe(self).priority_subject).reflection.foreign_key
    end

    sig { returns(T.nilable(Integer)) }
    def subject_id
      read_attribute(subject_id_column)
    end

    sig { returns(T.untyped) }
    def subject
      @subject ||= T.let(send(T.unsafe(self).priority_subject), T.untyped)
    end

    sig { returns(T.any(Symbol, String)) }
    def context_column
      association(T.unsafe(self).priority_context).reflection.foreign_key
    end

    sig { returns(T.nilable(Context)) }
    def context
      send(self.class.priority_context)
    end

    sig { returns(String) }
    def kind
      self.class.name.underscore
    end

    sig { params(column_name: Symbol).returns(T::Boolean) }
    def binary_column?(column_name)
      self.class.columns_hash[column_name.to_s]&.type == :binary
    end

    sig { params(new_context: T.untyped).returns(T.untyped) }
    def reparent(new_context)
      write_attribute(context_column, new_context.id)
      write_attribute(:priority, nil)
    end

    # Private: The single point of reprioritization. Sets this record's
    # priority to the given `to` value, shifting siblings around only if
    # required to make room for the reprioritization.
    #
    #   from         - (Optional) Integer value of the old priority
    #   to           - (Required) Integer value of the new priority
    #
    sig do
      params(
        to: Integer,
        from: T.nilable(Integer),
        association: T.any(T.nilable(Symbol), T.nilable(String)),
        dual_write: T.nilable(SBT::Context::PendingPriorityUpdate),
      ).void
    end
    def change_priority(to:, from: nil, association: nil, dual_write: nil)
      old_priority = from || self.raw_priority
      new_priority = to
      return if old_priority == new_priority

      shift_is_required = false
      moves = T.let(0, T.nilable(Integer))

      if siblings(include_self: true).where(priority: new_priority).exists?
        shift_is_required = true

        if ensure_not_in_transactions?
          # Since MySQL transactions use REPEATABLE READ isolation level by default, it means that logic within a transaction does not see actual up-to-date state,
          # but a snapshot of the data at the moment transaction started.
          # Since reprioritisation is a frequent operation it is possible to have one transaction overwrite updates from concurrent transaction.
          # In order to minimise the possibility of such race condition we'd like to shrink the time window of the transaction. This way it's less possible that the data we operate on is outdated.
          # For that reason we don't allow wrapping this method within a transaction.

          GitHub.dogstats.increment("#{kind}.prioritization.error.no_nested_transactions")
          raise CannotReprioritizeInNestedTransactionError, open_transaction_count
        end
      end

      self.class.transaction do
        if shift_is_required
          # Get this one out of the way while we shift things around
          update_attribute(:priority, MAX_PRIORITY_VALUE) if prioritized?

          begin
            moves = if old_priority && old_priority > new_priority
              self.class.shift_priorities_down(new_priority, context_column: context_column, context_id: context_id)
            else
              self.class.shift_priorities_up(new_priority, context_column: context_column, context_id: context_id)
            end
          rescue MovedTooFarError
            # Trigger an async rebalance before throwing an error
            T.unsafe(context).rebalance(association: association)
            raise RebalanceRequiredError
          end
        end

        T.unsafe(self).priority = new_priority
        dual_write&.apply
        # See https://github.com/github/github/pull/327225#issuecomment-2144683926 and https://github.com/github/github/pull/324959#pullrequestreview-2062046257
        # for our investigation and reasoning on whether to add a bang and validation here and in other instances of `self.save(validate: false)` in this file
        self.save(validate: false)
      end

      T.unsafe(context).rebalance(association: association) if moves.to_i > MOVES_THRESHOLD_FOR_REBALANCE

      [self, context, subject].each do |entity|
        entity.notify_subscribers if entity.respond_to?(:notify_subscribers)
      end

      nil
    end

    sig { params(column_name: T.any(Symbol, String)).returns(String) }
    def safe_column(column_name)
      self.class.connection.quote_column_name(column_name)
    end

    # Private: Moves this IssuePriority to the logical first position in the
    # list. Does not update any other IssuePriority records.
    #
    # Returns self.
    sig do
      type_parameters(:E)
      .params(
        association: T.any(T.nilable(Symbol), T.nilable(String)),
        dual_write: T.nilable(SBT::Context::PendingPriorityUpdate)
      )
      .returns(T.untyped)
    end
    def move_to_top(association: nil, dual_write: nil)
      return insert_at_top(association: association, dual_write:) if new_record?
      return T.cast(self, T.type_parameter(:E)) if T.unsafe(self).priority.present? && !siblings.exists?

      current_max = siblings.maximum(:priority)

      if current_max
        change_priority(to: current_max + GAP_SIZE, association: association, dual_write:)
      else
        self[:priority] = START_VALUE
        dual_write&.apply
        save!
      end

      T.cast(self, T.type_parameter(:E))
    end

    # Private: Inserts this record with the highest priority for the context.
    # Uses GitHub::SQL to determine the top priority to use, and saves the
    # record using ActiveRecord. Rescues on unique index priority collisions
    # in the event of race conditions.
    #
    # NOTE: If this record has already been persisted, falls back to `move_to_top`.
    #
    # Returns the current priority record.
    sig do
      type_parameters(:E)
      .params(
        association: T.any(T.nilable(Symbol),
        T.nilable(String)),
        dual_write: T.nilable(SBT::Context::PendingPriorityUpdate)
      )
      .returns(T.untyped)
    end
    def insert_at_top(association: nil, dual_write: nil)
      return move_to_top(association: association, dual_write:) if persisted?

      # Exit before insertion if there are errors on any attrs other than
      # priority (since we're going to let MySQL determine priority)
      if !valid? && errors.attribute_names != [:priority]
        T.bind(self, T.type_parameter(:E))
        return self
      end

      priority_value_sql = Arel.sql(<<-SQL, context_id: context_id)
        SELECT IFNULL(MAX(#{safe_column(:priority)}),#{START_VALUE}) + #{GAP_SIZE}
        FROM #{self.class.quoted_table_name}
        WHERE #{safe_column(context_column)} = :context_id FOR UPDATE
      SQL

      T.unsafe(self).priority = self.class.connection.select_value(priority_value_sql)
      dual_write&.apply

      begin
        self.save(validate: false)
        T.cast(self, T.type_parameter(:E))
      rescue ActiveRecord::RecordNotUnique => error
        if has_unique_subject_key? && error.message.match?(/key .#{unique_subject_key}./)
          # if there's been a race condition due to prioritization within the subject
          # this can happen if the issue is already assigned to the milestone
          self.class.find_by(issue_id: T.unsafe(self).issue_id, milestone_id: T.unsafe(self).milestone_id)
        else
          raise
        end
      end
    end

    # Private: Moves this object to the logical last position in the
    # list.
    #
    # Returns self.
    sig do
      type_parameters(:E)
      .params(
        association: T.any(T.nilable(Symbol),
        T.nilable(String)),
        dual_write: T.nilable(SBT::Context::PendingPriorityUpdate)
      )
      .returns(T.untyped)
    end
    def move_to_bottom(association: nil, dual_write: nil)
      return insert_at_bottom(association:, dual_write:) if new_record?
      return T.cast(self, T.type_parameter(:E)) if T.unsafe(self).priority.present? && !siblings.exists?

      current_min = siblings.minimum(:priority)

      if current_min
        new_priority = current_min - GAP_SIZE

        if new_priority < 0
          # rebalance the priorities so there is more room for records at the
          # bottom and in between siblings
          GitHub.dogstats.increment("#{kind}.prioritization.rebalance.priority_out_of_range")
          T.unsafe(context).rebalance!(association:)
          new_priority = siblings.minimum(:priority) - GAP_SIZE
        end
        change_priority(to: new_priority, association:, dual_write:)
      else
        self[:priority] = START_VALUE
        dual_write&.apply
        save!
      end

      T.cast(self, T.type_parameter(:E))
    end

    # Private: Inserts this record with the lowest priority for the context.
    # Uses GitHub::SQL to determine the current lowest available priority and
    # saves the card using ActiveRecord. Rescues on unique index priority
    # collisions in the event of race conditions.
    #
    # NOTE: If this record has already been persisted, falls back to `move_to_bottom`.
    #
    # Returns the current priority record.
    sig do
      type_parameters(:E)
      .params(
        association: T.any(T.nilable(Symbol),
        T.nilable(String)),
        dual_write: T.nilable(SBT::Context::PendingPriorityUpdate)
      )
      .returns(T.untyped)
    end
    def insert_at_bottom(association: nil, dual_write: nil)
      return move_to_bottom(association:, dual_write:) if persisted?

      # Exit before insertion if there are errors on any attrs other than
      # priority (since we're going to let MySQL determine priority)
      if !valid? && errors.attribute_names != [:priority]
        return T.cast(self, T.type_parameter(:E))
      end

      priority = minimum_priority_value

      if priority < 0
        # rebalance the priorities so objects can safely be prioritized at the bottom
        GitHub.dogstats.increment("#{kind}.prioritization.rebalance.priority_out_of_range")
        T.unsafe(context).rebalance!(association:)
        priority = minimum_priority_value
      end

      T.unsafe(self).priority = priority
      dual_write&.apply

      begin
        self.save(validate: false)
        self
      rescue ActiveRecord::RecordNotUnique => error
        if has_unique_subject_key? && error.message.match?(/key .#{unique_subject_key}./)
          # if there's been a race condition specifically due to prioritization during save,
          # we know the record was safely saved and can return it here.
          self.class.find_by(issue_id: T.unsafe(self).issue_id, milestone_id: T.unsafe(self).milestone_id)
        else
          raise
        end
      end
    end

    # Private: The unique (database) index enforcing uniqueness for subjects
    # within a context.
    #
    # Example: index_issue_priorities_on_issue_id_and_milestone_id
    #
    # Returns a String index name or nil.
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    sig { returns(T.nilable(String)) }
    def unique_subject_key
      begin
        unique_pair = [subject_id_column, context_column]
        index = self.class.connection.indexes(self.class.table_name)&.detect do |index|
          # find indicies matching the suject and context, and allow for polymorphic subject relationships
          index.unique && (index.columns & unique_pair) == unique_pair
        end
        index&.name
      end
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    sig { returns(T::Boolean) }
    def has_unique_subject_key?
      !!unique_subject_key
    end

    # Private: Inserts or moves this record to a higher logical priority
    # than the given subject. Updates any priority records in between. Can move
    # no more than MAX_MOVES away from the current logical position to prevent
    # expensive mass updates.
    #
    #   subject - the subject (e.g. Issue) we want to shift this priority
    #             directly above
    #
    # Returns nothing.
    sig do
      type_parameters(:E)
      .params(
        subject: T.all(T.type_parameter(:E), ApplicationRecord::Base),
        association: T.any(T.nilable(Symbol), T.nilable(String)),
        dual_write: T.nilable(SBT::Context::PendingPriorityUpdate)
      )
      .returns(T.untyped)
    end
    def insert_before(subject, association: nil, dual_write: nil)
      return insert_at_top(association: association, dual_write:) unless persisted? && prioritized?
      return insert_after(siblings.last, association: association, dual_write:) if !subject

      if subject.class == self.class
        priority_below = subject
      else
        conditions = { subject_id_column => subject.id }
        conditions.merge(subject_type: T.unsafe(subject).type) if subject_is_polymorphic?
        return T.cast(self, T.type_parameter(:E)) unless priority_below = siblings.where(conditions).first
      end

      return insert_at_top(association:, dual_write:) if priority_below.highest_priority?

      old_priority = T.unsafe(self).priority

      if old_priority > priority_below.raw_priority
        new_priority = priority_below.raw_priority + 1
      else
        new_priority = priority_below.raw_priority
      end

      change_priority(from: old_priority, to: new_priority, association: association, dual_write:)

      T.cast(self, T.type_parameter(:E))
    end

    # Private: Inserts or moves this record to a lower logical priority than
    # the given subject. Updates any priority records in between. Can move no
    # more than MAX_MOVES away from the current logical position to prevent
    # expensive mass updates.
    #
    #   subject - the record (e.g. Issue) we want to shift this priority
    #             directly underneath
    #
    # Returns nothing.
    sig do
      type_parameters(:E)
      .params(
        subject: T.untyped,
        association: T.any(T.nilable(Symbol), T.nilable(String)),
        dual_write: T.nilable(SBT::Context::PendingPriorityUpdate)
      )
      .returns(T.untyped)
    end
    def insert_after(subject, association: nil, dual_write: nil)
      return insert_at_bottom(association: association, dual_write:) unless T.unsafe(context).prioritized?(association: association)

      if subject.class == self.class
        priority_above = subject
      else
        return T.cast(self, T.type_parameter(:E)) unless priority_above = siblings.where(subject_id_column.to_sym => subject.id).first
      end

      old_priority = raw_priority.to_i
      cursor = priority_above.raw_priority

      if !prioritized? || old_priority < cursor
        new_priority = cursor - 1
      else
        new_priority = cursor
      end

      change_priority(from: old_priority, to: new_priority, association: association, dual_write:)

      T.cast(self, T.type_parameter(:E))
    end

    sig { returns(Integer) }
    def open_transaction_count
      self.class.connection.open_transactions
    end

    sig { returns(T::Boolean) }
    def ensure_not_in_transactions?
      return false if GitHub.enterprise?
      open_transaction_count > MAX_TRANSACTION_NESTING_LEVELS
    end

    # Internal
    # Returns the lowest possible priority for insertion at the bottom
    sig { returns(Numeric) }
    def minimum_priority_value
      priority_value_sql = Arel.sql(<<-SQL, context_id: context_id)
        SELECT IFNULL(MIN(#{safe_column(:priority)}),#{START_VALUE}) - #{GAP_SIZE}

        FROM #{self.class.quoted_table_name}
        WHERE #{safe_column(context_column)} = :context_id FOR UPDATE
      SQL

      self.class.connection.select_value(priority_value_sql)
    end

    module ClassMethods
      extend T::Helpers

      sig { params(new_priority: Integer, context_column: T.any(String, Symbol), context_id: Integer).returns(T.untyped) }
      def shift_priorities_up(new_priority, context_column:, context_id:)
        sql_bindings = {
          table_name: Arel.sql(T.unsafe(self).quoted_table_name.to_s),
          priority_column: Arel.sql(:priority.to_s),
          context_column: Arel.sql(context_column.to_s),
          context_id: context_id,
          new_priority: new_priority,
        }

        # Decrementing down from new_priority, find the first priority that has
        # a gap after it.
        #
        # Note: do not try to move this into a subquery of the UPDATE query, as
        # MySQL doesn't allow subqueries on the table being updated.
        sql = Arel.sql <<-SQL, **sql_bindings
          SELECT t1.:priority_column
          FROM :table_name t1
          LEFT OUTER JOIN :table_name t2 ON t2.:context_column = t1.:context_column AND t2.:priority_column = (t1.:priority_column - 1)
          WHERE t1.:context_column = :context_id
          AND t1.:priority_column <= :new_priority
          AND t2.id IS NULL
          ORDER BY t1.:priority_column DESC
          LIMIT 1
        SQL

        T.unsafe(self).transaction do
          highest_priority_before_gap = T.unsafe(self).connection.select_value(sql)
          window_size = new_priority - highest_priority_before_gap + 1

          if window_size > MAX_MOVES
            T.bind(self, Kernel)
            raise MovedTooFarError, window_size
          else
            measure_shift do
              records_in_window = T.unsafe(self).where("
                #{context_column} = ? AND
                priority <= ? AND
                priority >= ?",
                context_id, new_priority, highest_priority_before_gap
              )
              records_in_window.order("priority ASC").update_all("priority = priority - 1")
            end
          end
        end
      end

      sig { params(new_priority: Integer, context_column: T.any(Symbol, String), context_id: Integer).returns(T.untyped) }
      def shift_priorities_down(new_priority, context_column:, context_id:)
        sql_bindings = {
          table_name: Arel.sql(T.unsafe(self).quoted_table_name.to_s),
          priority_column: Arel.sql(:priority.to_s),
          context_column: Arel.sql(context_column.to_s),
          context_id: context_id,
          new_priority: new_priority,
        }

        # Incrementing up from new_priority, find the first priority that has
        # a gap after it.
        #
        # Note: do not try to move this into a subquery of the UPDATE query, as
        # MySQL doesn't allow subqueries on the table being updated.
        sql = Arel.sql <<-SQL, **sql_bindings
          SELECT t1.:priority_column
          FROM :table_name t1
          LEFT OUTER JOIN :table_name t2 ON t2.:context_column = t1.:context_column AND t2.:priority_column = (t1.:priority_column + 1)
          WHERE t1.:context_column = :context_id
          AND t1.:priority_column >= :new_priority
          AND t2.id IS NULL
          ORDER BY t1.:priority_column ASC
          LIMIT 1
        SQL

        T.unsafe(self).transaction do
          lowest_priority_before_gap = T.unsafe(self).connection.select_value(sql)
          window_size = lowest_priority_before_gap - new_priority + 1

          if window_size > MAX_MOVES
            T.bind(self, Kernel)
            raise MovedTooFarError, window_size
          else
            measure_shift do
              records_in_window = T.unsafe(self).where("
                #{context_column} = ? AND
                priority <= ? AND
                priority >= ?",
                context_id, lowest_priority_before_gap, new_priority
              )
              records_in_window
                .order("priority DESC")
                .update_all("priority = priority + 1")
            end
          end
        end
      end

      sig { returns(Symbol) }
      def context_reflection
        T.unsafe(self).reflect_on_association(T.unsafe(self).priority_context).inverse_of.name
      end

      private

      sig { params(subject: Symbol, context: Symbol).void }
      def prioritizable_by(subject:, context:)
        T.unsafe(self).define_singleton_method(:priority_subject) { subject }
        T.unsafe(self).define_singleton_method(:priority_context) { context }

        T.unsafe(self).define_method(:priority_subject) { subject }
        T.unsafe(self).define_method(:priority_context) { context }

        T.unsafe(self).class_eval <<-RUBY, __FILE__, __LINE__ + 1
          scope :by_priority, -> { order("priority DESC") }
        RUBY
      end

      # Private: Wrapper for shifting a range of records up or down in
      # priority. Measures the time it takes the shift query to complete and
      # increments a Datadog counter responsible for keeping track of how many
      # records we're shifting (between 1 and MAX_MOVES), bucketed in range
      # groups of 5.
      #
      # Requires a block, which should execute the shift query and return the
      # number of records modified (as .update_all does).
      #
      # Returns nothing.
      sig { params(block: Proc).returns(Integer) }
      def measure_shift(&block)
        count = Instrumentation.track_time("#{T.unsafe(self).name.underscore}.shift_priorities.dist.time") do
          block.call
        end

        shift_groups = (1..MAX_MOVES).to_a.in_groups_of(25, false)
        shift_buckets = ({}).tap do |buckets|
          shift_groups.map do |group|
            buckets["#{group.first}-#{group.last}"] = group
          end
        end

        if bucket = shift_buckets.detect { |_k, v| v.include?(count) }.first
          GitHub.dogstats.increment "#{T.unsafe(self).name.underscore}.shift_priorities_count.#{bucket}"
        else
          # This should never happen.
          GitHub.dogstats.increment "#{T.unsafe(self).name.underscore}.shift_priorities_count.out-of-range"
        end

        count
      end
    end

    class CannotReprioritizeInNestedTransactionError < StandardError
      sig { params(value: T.untyped).void }
      def initialize(value)
        super "Cannot shift inside of nested transaction (current nesting depth is #{value})"
      end
    end

    class ConflictingPrioritizationArgumentError < ArgumentError; end

    class MovedTooFarError < StandardError
      sig { params(value: T.untyped).void }
      def initialize(value)
        super "Cannot shift #{value.inspect} positions - max is #{MAX_MOVES}"
      end
    end

    class RebalanceRequiredError < StandardError
      sig { void }
      def initialize
        super "Prioritization failed due to required rebalance"
      end
    end

    mixes_in_class_methods(ClassMethods)
  end
end
