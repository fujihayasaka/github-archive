# typed: true
# frozen_string_literal: true

class LegalHold < ApplicationRecord::Domain::Users
  include ::Users::BelongsToUser
  belongs_to_user_via_domain
  validates :user_id, presence: true, uniqueness: true
end
