# typed: true
# frozen_string_literal: true

class ClassroomUser < ApplicationRecord::Domain::Users
  belongs_to :user
  has_many :instructors, class_name: "ClassroomInstructor", dependent: :destroy

  validates :user, presence: true
  validates :user, uniqueness: true

  def verified_teacher?
    coupon_code.starts_with?("faculty-")
  end

  private

  def coupon_code
    String(user&.coupon&.code)
  end
end
