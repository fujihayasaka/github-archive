# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Elastomer

  class PartialBackfillReconciler < Elastomer::Reconciler

    attr_reader :start_date_time
    attr_reader :end_date_time
    attr_reader :updated_at_cursor_key

    def initialize(opts)
      super(opts)

      @start_date_time = opts.fetch(:start_date_time)
      @end_date_time = opts.fetch(:end_date_time) { Time.now }
      @updated_at_cursor_key = "#@type/updated_at_cursor"
    end

    # Internal: Get the timestamp cursor from redis.
    #
    # Returns a datettime String.
    def get_updated_at_cursor
      redis.hget(group_key, updated_at_cursor_key) || start_date_time
    end

    # Internal: Set the updated_at_cursor in redis. This should only be called while
    # guarded by a shared mutex. See the `models` method further down.
    #
    # Returns an integer: the number of fields that were added.
    def set_updated_at_cursor(cursor)
      redis.hset(group_key, updated_at_cursor_key, cursor)
    end

    # Override canonical methods to include time-based constraints for partial backfill
    sig { params(offset: Integer).returns(String) }
    def canonical_conditions(offset)
      updated_at_cursor = get_updated_at_cursor
      conds = "#{model_class.table_name}.id > #{model_class.connection.quote(offset)}"
      conds << " AND #{model_class.table_name}.updated_at >= #{model_class.connection.quote(updated_at_cursor)}"
      conds << " AND #{model_class.table_name}.updated_at <= #{model_class.connection.quote(end_date_time)}"

      if conditions.present?
        if conditions.respond_to?(:call)
          condition = conditions.call(self, *proc_args)
          if condition.present?
            conds << " AND #{condition}"
          end
        else
          conds << " AND #{conditions}"
        end
      end
      conds
    end

    def canonical_base_query(offset)
      conds = canonical_conditions(offset)
      order = "#{model_class.table_name}.updated_at ASC, #{model_class.table_name}.id ASC"
      canonical_scope_with_annotations.where(conds).limit(limit).order(order).joins(joins)
    end

    sig { override.returns(T::Array[Symbol]) }
    def additional_mutex_columns
      [:updated_at]
    end

    # Hook to update the cursor after models are processed
    def post_process_plucked_columns(rows)
      updated_at_cursor = get_updated_at_cursor
      if updated_at_cursor && end_date_time && !rows.empty?
        updated_at_datetime = rows.last.last.to_datetime.new_offset(0)
        set_updated_at_cursor(updated_at_datetime.iso8601)
      end
    end
  end
end
