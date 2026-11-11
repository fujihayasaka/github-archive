# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"


# This transition marks push protection bypass exemption requests as approved,
# if their latest ExemptionResponse is approved and the request status is not already approved.

# The reason for this transition is because it turns out that you need to manually
# mark exemption requests as approved, in order for the org/enterprise request list filtering
# to work correctly when filtering by approved status.
#
# We've fixed this now, but this transition updates old requests.
module GitHub
  module Transitions
    class MarkPushProtectionBypassExemptionRequestsAsApproved < Base

      class ExemptionRequest < ApplicationRecord::Domain::Repositories
        self.table_name = :exemption_requests
      end

      class ExemptionResponse < ApplicationRecord::Domain::Repositories
        self.table_name = :exemption_responses
      end

      iterate_over :database_table, params: {
        model_class: ExemptionRequest,
        # push protection bypass requests, with a 'pending' status
        conditions: "request_type = 'secret_scanning' AND status = 0",
        columns: %i[status],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        exemption_request_ids = items.keys
        log "Processing exemption request IDs: #{exemption_request_ids.inspect}"
        responses_by_request_id = {}
        responses = ExemptionResponse.where(exemption_request_id: exemption_request_ids).order(created_at: :desc)
        responses.each do |response|
          responses_by_request_id[response.exemption_request_id] ||= []
          responses_by_request_id[response.exemption_request_id] << response
        end

        exemption_request_ids.each do |exemption_request_id|
          next unless responses_by_request_id[exemption_request_id].present? && responses_by_request_id[exemption_request_id].size > 0

          # Because the ExemptionResponse query is ordered by created_at desc, the first item in each array is the latest response.
          latest_response = responses_by_request_id[exemption_request_id].first
          if latest_response.status == Exemptions::ExemptionResponse::STATUSES[:approved] && T.must(items[exemption_request_id])[:status] != Exemptions::ExemptionRequest::STATUSES[:approved]
            if dry_run?
              log "Would have updated exemption request #{exemption_request_id} to approved"
            else
              log "Updating exemption request #{exemption_request_id} to approved"
              write_to(model_class: ExemptionRequest) do
                ExemptionRequest.where(id: exemption_request_id).update(status: Exemptions::ExemptionRequest::STATUSES[:approved])
              end
            end
          end
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::MarkPushProtectionBypassExemptionRequestsAsApproved.new(args).run
end
