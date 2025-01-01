# typed: true
# frozen_string_literal: true

class MemexProject
  class VisitedAfterReconciler < MemexProjectItems::Reconciler

    DEFAULT_VISITED_AFTER = 30.days

    # Delimiter used to separate the last visited date and the memex project id.
    CURSOR_DELIMITER = "#"

    # The date where a MemexProject has to have been last visited since. Used to filter projects and prepare
    # batches to reconcile. (optional, default: 30 days ago)
    attr_reader :visited_after

    def initialize(opts)
      super(opts)

      @visited_after = opts.fetch(:visited_after) { DEFAULT_VISITED_AFTER.ago.to_date }
    end

    sig { returns(Integer) }
    def last_id
      memex_project_id = MemexProject.connection.select_value(Arel.sql <<-SQL, visited_after:)
        SELECT id
        FROM memex_projects
        WHERE last_visited_on >= :visited_after
        ORDER BY id DESC
        LIMIT 1
      SQL

      memex_project_id || 0
    end

    sig { returns(Float) }
    def progress
      last = last_id
      return 0.0 unless last > 0

      (last_memex_project_id.to_f / last.to_f) * 100.0
    end

    sig { returns(Date) }
    def last_visited_on
      date, = get_offset
      date
    end

    sig { returns(Integer) }
    def last_memex_project_id
      _date, last_memex_project_id = get_offset

      last_memex_project_id
    end

    sig { returns([Date, Integer]) }
    def get_offset
      if (offset = redis.hget(group_key, offset_key))
        date, memex_project_id = offset.split(CURSOR_DELIMITER)

        [Date.iso8601(date), memex_project_id.to_i]
      else
        [visited_after, 0]
      end
    end

    sig { returns(T::Array[Integer]) }
    def calculate_reconciler_batch
      mutex.lock do
        GitHub.dogstats.time "memex_project.reconciler.prepare_batch", tags: ["index:#{index.name}"] do
          last_visited_on, memex_project_id = get_offset
          memex_projects = T.let([], T::Array[[DateTime, Integer]])
          memex_project_ids = T.let([], T::Array[Integer])

          memex_projects = MemexProject.connection.select_rows(Arel.sql <<-SQL, last_visited_on:, memex_project_id:)
            SELECT last_visited_on, id
            FROM memex_projects
            WHERE last_visited_on > :last_visited_on OR (last_visited_on = :last_visited_on AND id > :memex_project_id)
            ORDER BY last_visited_on ASC, id ASC
            LIMIT #{limit}
          SQL

          if (last_memex_project = memex_projects.last)
            last_visited_on, memex_project_id = last_memex_project
            memex_project_ids = memex_projects.collect(&:second)

            set_reconciler_batch(memex_project_ids)
            set_offset(last_visited_on, memex_project_id)
          end

          memex_project_ids
        end
      end
    end

    private

    sig { params(last_visited_on: Date, memex_project_id: Integer).void }
    def set_offset(last_visited_on, memex_project_id)
      cursor = [last_visited_on.iso8601, memex_project_id].join(CURSOR_DELIMITER)
      redis.hset(group_key, offset_key, cursor)
    end
  end
end
