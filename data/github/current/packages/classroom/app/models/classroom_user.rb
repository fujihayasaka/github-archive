# typed: true
# frozen_string_literal: true

class ClassroomUser < ApplicationRecord::Domain::Users
  include ::Users::BelongsToUser
  belongs_to_user_via_domain
  destroy_in_background_with :user
  has_many :instructors, class_name: "ClassroomInstructor", dependent: :destroy

  validates :user_id, presence: true, on: :create
  validates :user, uniqueness: { allow_nil: true }

  def verified_teacher?
    coupon_code.starts_with?("faculty-")
  end

  private

  def coupon_code
    String(user&.coupon&.code)
  end
end
