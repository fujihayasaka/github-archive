# typed: true
# frozen_string_literal: true

class LegalHold < ApplicationRecord::Domain::Users
  belongs_to :user
  validates :user_id, presence: true, uniqueness: true
end
