# typed: strict
# frozen_string_literal: true

module InProductTargeting
  class Domain < GH::Domain::Base

    # Returns a metadata json object if there's a match or nil if not
    sig { params(user_id: T.nilable(Integer), cohort: T.nilable(String), day: T.nilable(String)).returns(T.nilable(T::Hash[String, T.untyped])) }
    def match?(user_id: nil, cohort: nil, day: nil)
      ::IpmMatch.find_by(user_id: user_id, cohort: cohort, day: day)&.metadata
    end

    # Creates multiple IpmMatches in bulk with the provided attributes
    sig { params(matches: T::Array[{ user_id: Integer, cohort: String, day: String, metadata: T::Hash[String, T.untyped] }]).returns(T::Boolean) }
    def bulk_create_matches(matches:)
      return true if matches.empty?

      GitHub.logger.info("Creating matches in bulk", {
        "in_product_targeting.matches_count" => matches.length
      })

      ActiveRecord::Base.connected_to(role: :writing) do
        # Prepare data for bulk insert
        current_time = Time.current
        records_to_insert = matches.map do |match|
          {
            user_id: match[:user_id],
            cohort: match[:cohort],
            day: match[:day],
            metadata: match[:metadata],
            created_at: current_time,
            updated_at: current_time
          }
        end

        begin
          # Use insert_all for bulk insertion without returning option
          # Check if the number of records exceeds the limit
          max_records = 500
          if records_to_insert.length > max_records
            error_message = "Bulk insert exceeds maximum allowed records (#{max_records})"
            GitHub.logger.error("Failed to bulk create IpmMatches", {
              "in_product_targeting.error" => error_message,
              "in_product_targeting.requested_count" => records_to_insert.length,
              "in_product_targeting.max_allowed" => max_records
            })
            raise ArgumentError, error_message
          end

          ::IpmMatch.insert_all(records_to_insert)

          # Get count instead of IDs since we can't use returning option
          count = records_to_insert.length

          GitHub.logger.info("Successfully bulk created IpmMatches", {
            "in_product_targeting.created_count" => count
          })

          # Return true to indicate success instead of IDs
          true
        rescue ActiveRecord::RecordNotUnique => e
          GitHub.logger.error("Duplicate record error during bulk insert", {
            "in_product_targeting.error" => e.message
          })
          raise e
        end
      end
    end

    # Deletes all IpmMatches for a specific day and cohort.
    #
    # @param day [String] The day in ISO 8601 format (YYYY-MM-DD).
    # @param cohort [String] The cohort identifier.
    # @return [Integer] The number of deleted matches.
    sig { params(day: String, cohort: String).returns(Integer) }
    def delete_matches_by_day_and_cohort(day:, cohort:)
      GitHub.logger.info("Deleting matches", {
        "in_product_targeting.day" => day,
        "in_product_targeting.cohort" => cohort
      })

      ActiveRecord::Base.connected_to(role: :writing) do
        begin
          # Delete the records
          result = ::IpmMatch.where(day: day, cohort: cohort).delete_all

          GitHub.logger.info("Successfully deleted IpmMatches", {
            "in_product_targeting.deleted_count" => result,
            "in_product_targeting.day" => day,
            "in_product_targeting.cohort" => cohort
          })

          result
        rescue ActiveRecord::ActiveRecordError => e
          GitHub.logger.error("Failed to delete IpmMatches", {
            "in_product_targeting.error" => e.message,
            "in_product_targeting.day" => day,
            "in_product_targeting.cohort" => cohort
          })
          raise e
        end
      end
    end

    # Deletes all IpmMatches with day on or before the specified day.
    #
    # @param day [String] The day in ISO 8601 format (YYYY-MM-DD).
    # @return [Integer] The number of deleted matches.
    sig { params(day: String).returns(Integer) }
    def delete_matches_on_or_before_day(day:)
      GitHub.logger.info("Deleting matches on or before day", {
        "in_product_targeting.day" => day
      })

      ActiveRecord::Base.connected_to(role: :writing) do
        begin
          # Parse the input day to ensure valid date format
          target_date = Date.parse(day)

          # Convert target date to string format appropriate for comparison
          target_date_str = target_date.to_s

          # Batch delete records to avoid performance issues with large deletes
          deleted_count = 0

          # Find all matches with day on or before the target date
          ::IpmMatch.where("day <= ?", target_date_str).in_batches do |batch|
            # Get the IDs first to avoid the "can't specify target table in FROM clause" error
            ids = batch.pluck(:id)
            # Delete records with those IDs
            deleted_count += ::IpmMatch.where(id: ids).delete_all
          end

          GitHub.logger.info("Successfully deleted IpmMatches on or before date", {
            "in_product_targeting.deleted_count" => deleted_count,
            "in_product_targeting.day" => day,
            "in_product_targeting.target_date" => target_date.to_s
          })

          deleted_count
        rescue ArgumentError => e
          GitHub.logger.error("Invalid date format for day parameter", {
            "in_product_targeting.error" => e.message,
            "in_product_targeting.day" => day
          })
          raise e
        rescue ActiveRecord::ActiveRecordError => e
          GitHub.logger.error("Failed to delete IpmMatches on or before date", {
            "in_product_targeting.error" => e.message,
            "in_product_targeting.day" => day
          })
          raise e
        end
      end
    end
  end
end
