# typed: true
# frozen_string_literal: true

require "monolith-twirp-copilot-limiter"

module CopilotLimiter
  module Twirp
    class InteractionsClient < CopilotLimiter::Twirp::BaseClient
      VALID_ENTITY_TYPES = %w[User Business Organization].freeze

      sig do
        params(
          entity_id: Integer,
          entity_type: String,
          user_id: Integer,
          start_date: T.nilable(T.any(Date, DateTime)),
          end_date: T.nilable(T.any(Date, DateTime)),
        ).returns(T::Boolean)
      end
      def generate_csv(entity_id:, entity_type:, user_id:, start_date:, end_date:)
        GitHub.logger.with_named_tags({
          "code.function": "generate_csv",
          "code.namespace": "CopilotLimiter::Twirp::InteractionsClient",
          "gh.copilot_limiter.entity_id": entity_id,
          "gh.copilot_limiter.entity_type": entity_type,
          "gh.copilot_limiter.interactions_start_date": start_date,
          "gh.copilot_limiter.interactions_end_date": end_date,
        }) do
          if !VALID_ENTITY_TYPES.include?(entity_type)
            GitHub.dogstats.increment(
              "copilot_limiter.interactions_client.error",
              tags: { method: "generate_csv", error: "entity_type_invalid" }
            )
            GitHub.logger.info("Invalid entity type, returning false")
            return false
          end

          if user_id.nil?
            GitHub.dogstats.increment(
              "copilot_limiter.interactions_client.error",
              tags: { method: "generate_csv", error: "user_id_invalid" }
            )
            GitHub.logger.info("No user id, returning false")
            return false
          end

          # Call the Limiter service to request premium interaction CSV report
          # The report will be generated async and the user will be notified via email
          GitHub.logger.info("Generating premium interactions report")
          response = rpc(
            :GenerateCSV,
            entity_id: entity_id,
            entity_type: entity_type,
            user_id: user_id,
            start_date: self.class.convert_to_limiter_date(start_date),
            end_date: self.class.convert_to_limiter_date(end_date),
          )
          GitHub.logger.info(
            "Finished Twirp Call",
            "gh.copilot_limiter.response.status": response&.status,
            "gh.copilot_limiter.response.value": response&.value,
            "gh.copilot_limiter.response.options": response&.options,
            "gh.copilot_limiter.response.call_succeeded": response&.call_succeeded,
          )

          if response.call_succeeded? && response.value.success
            GitHub.dogstats.increment("copilot_limiter.interactions_client.success", tags: { method: "generate_csv" })
            GitHub.logger.info(
              "Generated premium interactions report",
              "gh.copilot_limiter.interactions_request_id": response.value.request_id, # added request_id sorbet/rbi/dsl/monolith_twirp/copilot/limiter/v1/generate_csv_response.rbi
            )
            return true
          else
            GitHub.dogstats.increment(
              "copilot_limiter.interactions_client.error",
              tags: { method: "generate_csv", error: "limiter_request_failed" }
            )
            GitHub.logger.info("Failed to generate premium interactions report.")
            return false
          end
        end
      end

      sig do
        params(date: T.nilable(T.any(Date, DateTime))).returns(T.nilable(MonolithTwirp::Copilot::Limiter::V1::Date))
      end
      def self.convert_to_limiter_date(date)
        return nil if date.nil?
        MonolithTwirp::Copilot::Limiter::V1::Date.new(day: date.day, month: date.month, year: date.year)
      end

      private

      def twirp_class
        ::MonolithTwirp::Copilot::Limiter::V1::CopilotLimiterAPIClient
      end
    end
  end
end
