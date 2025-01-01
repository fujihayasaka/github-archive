# typed: true
# frozen_string_literal: true

class Codespaces::UnprocessedBillingMessage < ApplicationRecord::Domain::Codespaces

  self.table_name = "codespace_unprocessed_billing_messages"

  validates :message_id, presence: true, length: { is: 36 }
  validates :azure_storage_account_name, presence: true, length: { within: 3..24 }
  validates :body, presence: true

  scope :newest_to_oldest, -> { order("id DESC") }
end
