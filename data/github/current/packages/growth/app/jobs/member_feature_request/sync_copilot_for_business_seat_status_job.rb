# typed: strict
# frozen_string_literal: true

class MemberFeatureRequest::SyncCopilotForBusinessSeatStatusJob < BatchedJob

  queue_as :member_feature_request

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig do
    params(
      args: T.untyped,
      timestamp: T.nilable(Time),
      offset_item_id: T.nilable(Integer),
      progress: T.nilable(Integer),
      options: T.untyped
    ).returns(T.any(T::Array[MemberFeatureRequest], ActiveRecord::Relation))
  end
  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)

    MemberFeatureRequest
      .requested
      .where(feature: MemberFeatureRequest::Feature::CopilotForBusiness)
      .where("id > ?", offset_item_id)
      .limit(BATCH_SIZE)
      .order(id: :asc)
  end

  sig { params(requests: T.any(T::Array[MemberFeatureRequest], ActiveRecord::Relation), args: T.untyped, options: T.untyped).void }
  def process_batch(requests, *args, **options)
    requests.each do |request|
      next unless Copilot::Seat.where(assigned_user_id: request.requester_id, organization_id: request.organization_id).exists?

      MemberFeatureRequest::CopilotForBusinessSeatStatusJob.perform_later(
        organization_id: request.organization_id,
        user_id: request.requester_id
      )
    end
  end
end
