# typed: true
# frozen_string_literal: true

module Platform
  module Loaders

    # Calculates the creation velocity of associated records.
    # Note: Useful for identifying spammers.
    class AssociatedRecordCreationVelocity < Platform::Loader
      DEFAULT_INTERVAL = 3600 # seconds
      RETRY_DELAY_MILLISECONDS = 50

      def self.load(model, association, interval: DEFAULT_INTERVAL, retry_delay_milliseconds: RETRY_DELAY_MILLISECONDS)
        reflection = model.class.reflections[association.to_s]

        if reflection.nil?
          raise Errors::Internal.new("#{association} association does not exist on #{model.class}")
        end

        self.for(reflection, interval, retry_delay_milliseconds).load(model.id)
      end

      def initialize(reflection, interval, retry_delay_milliseconds)
        @reflection = reflection
        @interval = interval
        @retry_delay_milliseconds = retry_delay_milliseconds
      end

      def fetch(model_ids)
        stats = @reflection.klass.connection.select_rows(Arel.sql(<<-SQL, model_ids: model_ids))
          SELECT
            #{@reflection.foreign_key} AS foreign_key,
            count(id) AS count,
            min(id) AS first_id,
            max(id) AS last_id
          FROM #{@reflection.table_name}
          WHERE #{@reflection.foreign_key} IN (:model_ids)
          GROUP BY #{@reflection.foreign_key}
        SQL

        ids = stats
          .map { |row| [row.third, row.last] }
          .flatten
          .uniq

        tries = 3

        begin
          tries -= 1
          timestamps_by_id = @reflection.klass
            .select(:id, :created_at)
            .where(id: ids)
            .index_by(&:id)

          rows = stats.map do |key, count, first_id, last_id|
            [
              key,
              count,
              timestamps_by_id[first_id].created_at,
              timestamps_by_id[last_id].created_at
            ]
          end
        rescue NoMethodError => error
          sleep 0.001 * @retry_delay_milliseconds
          retry if tries > 0
        end

        model_ids.inject(Hash.new) do |result, model_id|
          _, count, first_timestamp, last_timestamp = (rows || []).find { |row| row[0] == model_id }
          velocity = 0

          if count && first_timestamp && last_timestamp && count > 2
            active_interval = last_timestamp.utc - first_timestamp.utc

            if active_interval > 0
              velocity = count / (active_interval / @interval).to_f
            end
          end

          result[model_id] = velocity.round
          result
        end
      end
    end
  end
end
