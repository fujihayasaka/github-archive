# typed: true
# frozen_string_literal: true

class CasMapping < ApplicationRecord::Domain::Users
  include GitHub::Validations
  include ::Users::BelongsToUser
  belongs_to_user_via_domain
  destroy_in_background_with :user
  validates :user_id, presence: true, on: :create
  validates :username, presence: true
  validates_uniqueness_of :username, case_sensitive: false
  validates :username, unicode3: true
end
