# typed: true
# frozen_string_literal: true

class BusinessFooterLink < ApplicationRecord::Domain::Users
  belongs_to :business
  validates :title, presence: { message: "Please enter a title for this link" }, length: { maximum: 80 }
  validates :url,
    presence: { message: "Please enter a URL for this link" },
    length: { maximum: 255 },
    format: {
      with: %r{\Ahttps://.+},
      message: "Must be a valid HTTPS URL (e.g., https://example.com)"
    }
end
