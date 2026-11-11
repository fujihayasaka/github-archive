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
          process_targeting_list(
            req: req,
            env: env,
            targetings: req.user_targetings,
            entity_id_field: :user_id,
            entity_name: "user"
          )
        end

        # Public: Implementation of the AddOrganizationTargetingList Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Targeting::Users::V1::AddOrganizationTargetingListRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Targeting::Users::V1::AddOrganizationTargetingListResponse, or a Twirp::Error.
        def add_organization_targeting_list(req, env)
          process_targeting_list(
            req: req,
            env: env,
            targetings: req.organization_targetings,
            entity_id_field: :organization_id,
            entity_name: "organization"
          )
        end

        # Public: Implementation of the AddEnterpriseTargetingList Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Targeting::Users::V1::AddEnterpriseTargetingListRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Targeting::Users::V1::AddEnterpriseTargetingListResponse, or a Twirp::Error.
        def add_enterprise_targeting_list(req, env)
          process_targeting_list(
            req: req,
            env: env,
            targetings: req.enterprise_targetings,
            entity_id_field: :enterprise_id,
            entity_name: "enterprise"
          )
        end

        private

        # Private: Common logic for processing targeting lists for users, organizations, or enterprises.
        #
        # req - The Twirp request object.
        # env - The Twirp environment as a Hash.
        # targetings - The array of targeting records (user_targetings, organization_targetings, or enterprise_targetings).
        # entity_id_field - The entity ID field name as a Symbol (:user_id, :organization_id, or :enterprise_id).
        # entity_name - The entity name as a String ("user", "organization", or "enterprise") for logging.
        #
        # Returns the Twirp response as a Hash with success and cohort_data, or a Twirp::Error.
        def process_targeting_list(req:, env:, targetings:, entity_id_field:, entity_name:)
          GitHub.logger.info("Processing add_#{entity_name}_targeting_list request", {
            "targeting.#{entity_name}_targetings.length" => targetings.respond_to?(:length) ? targetings.length : "N/A",
            "targeting.day" => req.day,
            "targeting.cohort" => req.cohort
          })

          begin
            GitHub.logger.info("Processing #{entity_name}_targetings", {
              "targeting.#{entity_name}_targetings.type" => targetings.class.to_s,
              "targeting.#{entity_name}_targetings.length" => targetings.respond_to?(:length) ? targetings.length : "N/A"
            })

            # Check if targetings is actually an array-like structure
            if !targetings.respond_to?(:map)
              GitHub.logger.error("Invalid #{entity_name}_targetings format", {
                "targeting.#{entity_name}_targetings.type" => targetings.class.to_s
              })

              if targetings.respond_to?(:to_a)
                targetings = targetings.to_a
                GitHub.logger.info("Converted #{entity_name}_targetings to Array", {
                  "targeting.#{entity_name}_targetings.length" => targetings.length
                })
              else
                return Twirp::Error.invalid_argument("Invalid #{entity_name}_targetings format: #{targetings.class}")
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

          if targetings.length > BATCH_SIZE
            GitHub.logger.error("Batch size exceeded", {
              "targeting.batch_size.max" => BATCH_SIZE,
              "targeting.batch_size.received" => targetings.length
            })
            return Twirp::Error.invalid_argument(
              "Too many records. Maximum allowed is #{BATCH_SIZE}, but received #{targetings.length}"
            )
          end

          GitHub.logger.info("Processing #{entity_name} targeting records", {
            "targeting.records_count" => targetings.length
          })

          # Create all records
          records_to_insert = []
          begin
            GitHub.logger.info("Preparing #{entity_name}_targetings batch", {
              "targeting.#{entity_name}_targetings.length" => targetings.length,
              "targeting.#{entity_name}_targetings.sample" => targetings.first.inspect
            }) if targetings.any?

            records_to_insert = targetings.map do |match|
              GitHub.logger.debug("Preparing match", {
                "targeting.match" => match.inspect,
                "targeting.match.type" => match.class.to_s
              })
              record = {
                entity_id_field => match[entity_id_field.to_s],
                :cohort => cohort.to_s, # Ensure cohort is a string
                :day => day.to_s,       # Ensure day is a string
                :metadata => match["metadata"],
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
            GitHub.logger.error("Error preparing #{entity_name}_targetings", {
              "error.class" => e.class.to_s,
              "error.message" => e.message,
              "error.backtrace" => e.backtrace&.join("\n")
            })
            return Twirp::Error.internal("Error preparing #{entity_name}_targetings: #{e.message}")
          end

          GitHub.logger.info("Creating new matches", {
            "targeting.records_to_create" => records_to_insert.length
          })

          begin
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

          # Calculate cohort counts from targeting records
          cohort_data = targetings.each_with_object(Hash.new(0)) do |_targeting, counts|
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

        public

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
