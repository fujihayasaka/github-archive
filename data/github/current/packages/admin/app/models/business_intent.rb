# typed: strict
# frozen_string_literal: true

class BusinessIntent < ApplicationRecord::Domain::Accounts
  enum :intent, {
    advanced_security: 0,
    code_security: 1,
    copilot_business: 2,
    enterprise: 3,
    enterprise_and_ado: 4,
    secret_protection: 5,
  }

  belongs_to :business, class_name: "Business"

  validates :business, presence: true
  validates :intent, presence: true
  validates :business_id, uniqueness: { scope: :intent }

  sig { params(business: Business, intent: Symbol).void }
  def self.create_or_update_intent(business:, intent:)
    existing_record = BusinessIntent.where(business: business).where(intent: intent).first
    if existing_record.present?
      existing_record.touch
    else
      BusinessIntent.new(business: business, intent: intent).save!
    end
  end
end
