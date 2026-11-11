# typed: true
# frozen_string_literal: true

class ClassroomClassroom < ApplicationRecord::Domain::Classroom
  has_many :assignments, class_name: "ClassroomAssignment", dependent: :destroy
  has_many :instructors, class_name: "ClassroomInstructor", dependent: :destroy

  validates :name, presence: true
  validates :name, length: { maximum: 255 }
end
