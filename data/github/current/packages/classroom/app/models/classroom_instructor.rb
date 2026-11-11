# typed: true
# frozen_string_literal: true

class ClassroomInstructor < ApplicationRecord::Domain::Classroom
  belongs_to :classroom_user
  # rubocop:todo Rails/InverseOf
  belongs_to :classroom, class_name: "ClassroomClassroom", foreign_key: :classroom_classroom_id
  # rubocop:enable Rails/InverseOf
end
