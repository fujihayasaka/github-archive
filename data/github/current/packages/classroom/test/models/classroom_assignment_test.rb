# typed: true
# frozen_string_literal: true

require "test_helper"

class ClassroomAssignmentTest < GitHub::TestCase
  test "records are destroyed when the parent classroom is destroyed" do
    @classroom_assignment = create :classroom_assignment
    @classroom_assignment.classroom.destroy

    refute ClassroomAssignment.find_by(id: @classroom_assignment.id)
  end
end
