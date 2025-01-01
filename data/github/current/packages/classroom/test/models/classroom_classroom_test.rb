# typed: true
# frozen_string_literal: true

require "test_helper"

class ClassroomClassroomTest < GitHub::TestCase
  test "validates name must be present" do
    classroom = build :classroom_classroom, name: nil

    assert_raises(ActiveRecord::RecordInvalid) { classroom.save! }
  end

  test "validates name length must not exceed 255 characters" do
    classroom = build :classroom_classroom, name: "a" * 256

    assert_raises(ActiveRecord::RecordInvalid) { classroom.save! }
  end
end
