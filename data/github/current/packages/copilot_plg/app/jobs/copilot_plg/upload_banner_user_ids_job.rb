# typed: strict
# frozen_string_literal: true

module CopilotPLG
  class UploadBannerUserIdsJob < ApplicationJob
    queue_as :copilot_feedback_banners
    retry_on_dirty_exit

    sig { params(user_ids: T::Array[String], slug: String).void }
    def perform(user_ids:, slug:)
      ActiveRecord::Base.connected_to(role: :writing) do
        user_ids.each do |user_id|
          CopilotPLG::KV.set(
            "user.#{slug}-visible.#{user_id}",
            true.to_json,
            expires: 30.days.from_now
          )
        end
      end
    end
  end
end
