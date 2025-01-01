# typed: strict
# frozen_string_literal: true

# Originally owned & implemented by the Billing team. ApplicationRecord Domain must remain as
# `Billing` due to DB naming conventions. Similarly with the class name, keep the `Vss` prefix even within
# the Licensing::Vss module is required for DB naming conventions.
module Licensing
  module Vss
    class VssSubscriptionEvent < ApplicationRecord::Domain::Billing
      enum :status, {
        unprocessed: "unprocessed",
        processed: "processed",
        failed: "failed",
        under_investigation: "under_investigation"
      }

      validates :investigation_notes, length: { maximum: 255 }

      scope :unsuccessful, -> { where(status: [:failed, :under_investigation]).order(id: :desc) }
    end
  end
end
