# typed: true
# frozen_string_literal: true

require "monolith-twirp-targeting-users"

module Api::Internal::Twirp::Targeting
  module Users
    module V1
      # Handler for the MonolithTwirp::Targeting::Users::V1::UserTargetingAPIService
      class UserTargetingAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["targeting"]
        handles_service MonolithTwirp::Targeting::Users::V1::UserTargetingAPIService

        BATCH_SIZE = 500

        def initialize
          super
          @in_product_targeting_domain = ::InProductTargeting.domain
        end

        # Public: Implementation of the AddUserTargetingList Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Targeting::Users::V1::AddUserTargetingListRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Targeting::Users::V1::AddUserTargetingListResponse, or a Twirp::Error.
        def add_user_targeting_list(req, env)
          GitHub.logger.info("Processing add_user_targeting_list request", {
            "targeting.user_targetings.length" => req.user_targetings.respond_to?(:length) ? req.user_targetings.length : "N/A",
            "targeting.day" => req.day,
            "targeting.cohort" => req.cohort
          })

          begin
            user_targetings = req.user_targetings
            GitHub.logger.info("Processing user_targetings", {
              "targeting.user_targetings.type" => user_targetings.class.to_s,
              "targeting.user_targetings.length" => user_targetings.respond_to?(:length) ? user_targetings.length : "N/A"
            })

            # Check if user_targetings is actually an array-like structure
            if !user_targetings.respond_to?(:map)
              GitHub.logger.error("Invalid user_targetings format", {
                "targeting.user_targetings.type" => user_targetings.class.to_s
              })

              if user_targetings.respond_to?(:to_a)
                user_targetings = user_targetings.to_a
                GitHub.logger.info("Converted user_targetings to Array", {
                  "targeting.user_targetings.length" => user_targetings.length
                })
              else
                return Twirp::Error.invalid_argument("Invalid user_targetings format: #{user_targetings.class}")
              end
            end

            day = req.day
            cohort = req.cohort

            GitHub.logger.info("Request parameters", {
              "targeting.day.type" => day.class.to_s,
              "targeting.day.value" => day,
              "targeting.cohort.type" => cohort.class.to_s,
              "targeting.cohort.value" => cohort
            })
          rescue NoMethodError, ArgumentError => e
            GitHub.logger.error("Error accessing request parameters", {
              "error.class" => e.class.to_s,
              "error.message" => e.message,
              "error.backtrace" => e.backtrace&.join("\n")
            })
            return Twirp::Error.internal("Error accessing request parameters: #{e.message}")
          end

          if user_targetings.length > BATCH_SIZE
            GitHub.logger.error("Batch size exceeded", {
              "targeting.batch_size.max" => BATCH_SIZE,
              "targeting.batch_size.received" => user_targetings.length
            })
            return Twirp::Error.invalid_argument(
              "Too many records. Maximum allowed is #{BATCH_SIZE}, but received #{user_targetings.length}"
            )
          end

          GitHub.logger.info("Processing user targeting records", {
            "targeting.records_count" => user_targetings.length
          })

          # Create all records
          records_to_insert = []
          begin
            GitHub.logger.info("Preparing user_targetings batch", {
              "targeting.user_targetings.length" => user_targetings.length,
              "targeting.user_targetings.sample" => user_targetings.first.inspect
            }) if user_targetings.any?

            records_to_insert = user_targetings.map do |match|
              GitHub.logger.debug("Preparing match", {
                "targeting.match" => match.inspect,
                "targeting.match.type" => match.class.to_s
              })
              record = {
                user_id: match["user_id"],
                cohort: cohort.to_s, # Ensure cohort is a string
                day: day.to_s,       # Ensure day is a string
                metadata: match["metadata"],
              }
              GitHub.logger.debug("Record prepared", {
                "targeting.record" => record.inspect
              })
              record
            end
            GitHub.logger.info("Records preparation complete", {
              "targeting.records_processed" => records_to_insert.length
            })
          rescue NoMethodError, ArgumentError, TypeError => e
            GitHub.logger.error("Error preparing user_targetings", {
              "error.class" => e.class.to_s,
              "error.message" => e.message,
              "error.backtrace" => e.backtrace&.join("\n")
            })
            return Twirp::Error.internal("Error preparing user_targetings: #{e.message}")
          end

          GitHub.logger.info("Creating new matches", {
            "targeting.records_to_create" => records_to_insert.length
          })

          begin
            # Check the API signature of bulk_create_matches

            # Based on the logs in the domain.rb file, it seems the method expects a named parameter 'matches:'
            @in_product_targeting_domain.bulk_create_matches(matches: records_to_insert)
            GitHub.logger.info("Bulk create operation complete")
          rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid, ArgumentError => e
            GitHub.logger.error("Error creating matches", {
              "error.class" => e.class.to_s,
              "error.message" => e.message,
              "error.backtrace" => e.backtrace&.join("\n")
            })
            return Twirp::Error.internal(e.message)
          end

          # Calculate cohort counts from user targeting records
          cohort_data = user_targetings.each_with_object(Hash.new(0)) do |_targeting, counts|
            # Ensure the key in cohort_data is a string
            counts[cohort.to_s] += 1
          end

          GitHub.logger.info("Request processed successfully", {
            "targeting.cohort_data" => cohort_data.inspect
          })

          # Return success response with actual cohort data
          {
            success: true,
            cohort_data: cohort_data,
          }
        end

        # Public: Implementation of the DeleteTargetingListsOnOrBeforeDay Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Targeting::Users::V1::DeleteTargetingListsOnOrBeforeDayRequest.
        #       req.day should be a date in the YYYY-MM-DD format.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Targeting::Users::V1::DeleteTargetingListsOnOrBeforeDayResponse, or a Twirp::Error.
        def delete_targeting_lists_on_or_before_day(req, env)
          GitHub.logger.info("Processing delete_targeting_lists_on_or_before_day request", {
            "targeting.request" => req.inspect
          })

          begin
            day = req.day

            GitHub.logger.info("Request parameters", {
              "targeting.day.type" => day.class.to_s,
              "targeting.day.value" => day
            })

            if day.nil? || day.empty?
              GitHub.logger.error("Invalid day parameter", {
                "targeting.day" => day
              })
              return Twirp::Error.invalid_argument("Day parameter is required and cannot be empty")
            end

            # Parse the day to ensure it's a valid date
            begin
              parsed_day = Date.parse(day.to_s)
              GitHub.logger.info("Parsed day", {
                "targeting.day.parsed" => parsed_day
              })
            rescue ArgumentError => e
              GitHub.logger.error("Invalid date format", {
                "targeting.day" => day,
                "error.message" => e.message
              })
              return Twirp::Error.invalid_argument("Invalid date format: #{e.message}")
            end

          rescue NoMethodError, ArgumentError => e
            GitHub.logger.error("Error accessing request parameters", {
              "error.class" => e.class.to_s,
              "error.message" => e.message,
              "error.backtrace" => e.backtrace&.join("\n")
            })
            return Twirp::Error.internal("Error accessing request parameters: #{e.message}")
          end

          GitHub.logger.info("Deleting targeting lists on or before day", {
            "targeting.day" => day
          })

          begin
            # Call the domain method to delete records on or before the given day
            deleted_count = @in_product_targeting_domain.delete_matches_on_or_before_day(day: day.to_s)
            GitHub.logger.info("Delete operation complete", {
              "targeting.deleted_count" => deleted_count
            })

            # Return success response (the proto only defines a success field)
            {
              success: true
            }
          rescue ActiveRecord::ActiveRecordError => e
            GitHub.logger.error("Error deleting matches", {
              "error.class" => e.class.to_s,
              "error.message" => e.message,
              "error.backtrace" => e.backtrace&.join("\n")
            })
            Twirp::Error.internal(e.message)
          end
        end
      end
    end
  end
end
