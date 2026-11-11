# typed: true
# frozen_string_literal: true

module GitHubModels
  module Stafftools
    class UserBlockForm < ApplicationForm
      sig { params(blocked: T::Boolean, latest_reason: T.nilable(String)).void }
      def initialize(blocked:, latest_reason:)
        @blocked = blocked
        @latest_reason = latest_reason
      end

      form do |f|
        T.bind(self, UserBlockForm)

        f.radio_button_group(
          name: "reason",
          label: "Reason for blocking",
          required: true,
          prompt: "Select a reason",
        ) do |reason_group|
          GitHubModels.domain.blocks.reasons.each do |reason|
            reason_group.radio_button(label: reason, value: reason, checked: @blocked && reason == @latest_reason)
          end
        end

        f.text_field(name: "additional_information", label: "Additional information",
          caption: "Link to issue or ICM, or add other supporting information.")

        f.submit(name: "submit", scheme: :danger, label: @blocked ? "Allow Models access" : "Block Models access")
      end
    end
  end
end
