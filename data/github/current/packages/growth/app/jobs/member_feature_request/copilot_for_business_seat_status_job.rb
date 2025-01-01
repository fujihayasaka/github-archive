# typed: strict
# frozen_string_literal: true

class MemberFeatureRequest::CopilotForBusinessSeatStatusJob < ApplicationJob
  extend T::Sig

  queue_as :member_feature_request

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(organization_id: Integer, user_id: Integer).void }
  def perform(organization_id:, user_id:)
    requests = MemberFeatureRequest.where(
      request_entity_id: organization_id,
      requester_id: user_id,
      feature: MemberFeatureRequest::Feature::CopilotForBusiness,
    ).requested

    # Maybe the request was deleted? At any rate, we don't need to set the status.
    return if requests.count.zero?

    # This should never happen as we have a validation to prevent multiple requests of the same feature
    if requests.count > 1
      GitHub.logger.error(
        "Found #{requests.count} CopilotForBusiness requests for organization #{organization_id} and user #{user_id}",
        {
          "code.namespace" => self.class.name,
          "code.function" => "perform",
        }
      )
      return
    end

    request = requests.first
    with_write do
      request.fulfilled!
    rescue ActiveRecord::RecordInvalid => e
      GitHub.logger.error(
        "Could not update CopilotForBusiness request for organization #{organization_id} and user #{user_id}",
        {
          "code.namespace": self.class.name,
          "code.function": "perform",
          "exception.message": e.message,
        }
      )
      request.destroy!
    end
  end
end
