# typed: true
# frozen_string_literal: true

class ClassroomAssignment < ApplicationRecord::Domain::Classroom
  # rubocop:todo Rails/InverseOf
  belongs_to :classroom, class_name: "ClassroomClassroom", foreign_key: :classroom_classroom_id
  # rubocop:enable Rails/InverseOf
  belongs_to :starter_code_repository, class_name: "Repository", optional: true

  has_many :classroom_repositories, dependent: :destroy

  validates :name, presence: true
  validates :name, length: { maximum: 60 }
  validates :assignment_type, presence: true
  validates :classroom_classroom_id, presence: true
end
