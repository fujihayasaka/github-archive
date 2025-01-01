# typed: true
# frozen_string_literal: true

require "test_helper"

class ClassroomInstructorTest < GitHub::TestCase
  test "records are destroyed when the associated classroom is destroyed" do
    classroom = create :classroom_classroom
    user = create :classroom_user
    instructor = create :classroom_instructor, classroom_classroom_id: classroom.id, classroom_user_id: user.id

    classroom.destroy

    refute ClassroomInstructor.find_by(id: instructor.id)
  end

  test "records are destroyed when the associated user is destroyed" do
    classroom = create :classroom_classroom
    user = create :classroom_user
    instructor = create :classroom_instructor, classroom_classroom_id: classroom.id, classroom_user_id: user.id

    user.destroy

    refute ClassroomInstructor.find_by(id: instructor.id)
  end
end
