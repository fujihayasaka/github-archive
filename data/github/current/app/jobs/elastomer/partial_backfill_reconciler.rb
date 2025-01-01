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
    # Returns a redis success / error code.
    def set_updated_at_cursor(cursor)
      redis.hset(group_key, updated_at_cursor_key, cursor)
    end

    # Internal: Read the next set of ActiveRecord models to operate on. This
    # will lock the redis mutex and update the offset when the models are
    # loaded.
    #
    # Returns the Array of ActiveRecord model instances.
    def models
      return @models if defined? @models
      @models = nil
      @id_range = nil

      @models = mutex.lock do
        offset = get_offset
        updated_at_cursor = get_updated_at_cursor

        conds = "#{model_class.table_name}.id > #{model_class.connection.quote(offset)}"
        conds << " AND #{model_class.table_name}.updated_at >= #{model_class.connection.quote(updated_at_cursor)}"
        conds << " AND #{model_class.table_name}.updated_at <= #{model_class.connection.quote(end_date_time)}"
        order = "#{model_class.table_name}.updated_at ASC, #{model_class.table_name}.id ASC"
        if conditions.present?
          if conditions.respond_to?(:call)
            conds << " AND #{conditions.call(self, *proc_args)}"
          else
            conds << " AND #{conditions}"
          end
        end
        includes = ar_includes if ar_includes.present?

        scope = model_class
        if model_scope.respond_to?(:call)
          scope = model_scope.call(scope)
        end
        query = scope.annotate("cross-shard-query-exempted").uniq!(:annotate).where(conds).limit(limit).order(order).joins(joins).preload(includes)

        ary = query.to_a
        unless ary.empty?
          prefills.each do |method|
            GitHub::PrefillAssociations.prefill_batch_method(ary, method)
          end

          set_offset(ary.last.id)
          if updated_at_cursor && end_date_time
            updated_at_datetime = ary.last.updated_at.to_datetime.new_offset(0)
            set_updated_at_cursor(updated_at_datetime.iso8601)
          end
          @id_range = if @delete_documents_from_es
            (offset + 1)..(ary.last.id)
          else
            ary.map &:id
          end
        end
        ary
      end
    rescue GitHub::Redis::Mutex::LockError
      GitHub.dogstats.increment("search.repair.lock_error", { tags: ["index:#{index.name}"] })
      nil
    end
  end
end
