# typed: false
# frozen_string_literal: true

# Internal: Belongs to a Restorable and provides methods for insert and ignore
# with batching and throttling.
#
# See the Restorable documentation for usage details.
class Restorable
  module TypeHelpers

    # Internal: Combines the insert_ignore_sql query with models converted
    # to value arrays to be used in #insert_ignore.
    #
    # restorable - Restorable parent instance.
    # models     - An array of models.
    def save_models(restorable, models)
      return if models.empty?

      GitHub.dogstats.histogram "restorable", models.size, tags: ["type:#{metric_name}", "action:save_models"]

      insert_ignore(insert_ignore_sql, values(restorable.id, models))
    end

    # Internal: Takes a query and an array of values to be run in SQL
    #
    # query - The sql query to be performed.
    # values - An array of values for the sql query.
    def insert_ignore(query, values)
      values.each_slice(100) do |slice|
        throttle do
          GitHub.dogstats.time "restorable", tags: ["type:#{metric_name}", "action:insert_ignore"] do
            self.connection.insert(Arel.sql(query, values: Arel::Nodes::ValuesList.new(slice)))
          end
        end
      end
    end

    def insert_ignore_sql
      raise NotImplementedError, "This method must be implemented in a subclass."
    end

    def values(restorable_id, models)
      raise NotImplementedError, "This method must be implemented in a subclass."
    end

    def metric_name
      raise NotImplementedError, "This method must be implemented in a subclass."
    end

    # Public: Handles the batching and throttling for a given scope.
    #
    # scope - the scope to batch and throttle
    def throttle_batches(scope)
      scope.find_in_batches do |batch|
        throttle do
          batch.each do |model|
            yield(model)
          end
        end
      end
    end

    # Internal: Measure and report the time it takes to restore settings.
    def measure_restore_time
      GitHub.dogstats.time("restorable", tags: ["type:#{metric_name}", "action:restore"]) { yield }
    end
  end
end
