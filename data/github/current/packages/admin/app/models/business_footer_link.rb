# typed: true
# frozen_string_literal: true

class BusinessFooterLink < ApplicationRecord::Domain::Users
  belongs_to :business
  validates :title, presence: true, length: { maximum: 80 }
  validates :url,
    presence: true,
    length: { maximum: 255 },
    format: {
      with: %r{\Ahttps://.+},
      message: "is not a valid https URL (only https is allowed)"
    }
end
