# typed: true
# frozen_string_literal: true

require "test_helper"

class ClassroomRepositoryTest < GitHub::TestCase
  include BackgroundDeletesTestHelpers

  fixtures do
    @org = create :organization
    @student = create :user
    @student_repo = create :repository, owner: @org
    @classroom_repo = create :classroom_repository, user: @student, repository: @student_repo
  end

  attr_reader :org, :student, :student_repo, :classroom_repo

  test "is deleted with repository" do
    classroom_repo = create :classroom_repository
    other_classroom_repo = create :classroom_repository

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = classroom_repo.repository
      config.expect_destroyed = [classroom_repo]
      config.expect_not_destroyed = [other_classroom_repo]
    end
  end

  context "#has_user_or_team" do
    test "is invalid if user and team are both present" do
      assert_predicate @classroom_repo, :valid?
      @classroom_repo.team = create(:team, organization: org)
      refute_predicate @classroom_repo, :valid?
    end

    test "is invalid if user and team are both nil" do
      assert_predicate @classroom_repo, :valid?
      @classroom_repo.user = nil
      refute_predicate @classroom_repo, :valid?
    end

    test "is valid if user is only present" do
      assert_predicate @classroom_repo, :valid?
    end

    test "is valid if team is only present" do
      @classroom_repo.user = nil
      @classroom_repo.team = create(:team, organization: org)
      assert_predicate @classroom_repo, :valid?
    end
  end

  context "#starter_code_repository" do
    test "returns repository if starter_code_repository is present" do
      starter_repo = create :repository
      new_student_repo = create :repository
      assignment = create :classroom_assignment, starter_code_repository: starter_repo
      create :classroom_repository, user: student, repository: new_student_repo, assignment: assignment

      assert_equal starter_repo, new_student_repo.starter_code_repository
    end

    test "returns nil if no starter_code_repository present" do
      assert_nil student_repo.starter_code_repository
    end
  end

  context "#creation_handled_by_classroom?" do
    test "returns true if the repo is a classroom repository with starter code" do
      starter_repo = create :repository
      new_student_repo = create :repository
      assignment = create :classroom_assignment, starter_code_repository: starter_repo
      create :classroom_repository, user: student, repository: new_student_repo, assignment: assignment

      assert_predicate new_student_repo, :creation_handled_by_classroom?
    end

    test "returns true if the repo is a repository with a classroom assignment" do
      repo = create :repository
      assignment = create :classroom_assignment
      repo.classroom_assignment = assignment

      assert_predicate repo, :creation_handled_by_classroom?
    end

    test "returns false if repo is a classroom repository that does not have starter code or a classroom assignment" do
      repo = create :repository
      refute_predicate repo, :creation_handled_by_classroom?
    end
  end

  context "#has_teacher_toolbox_coupon" do
    test "returns true when teacher has an education coupon" do
      coupon = create :coupon, code: "faculty-2021"
      @org.redeem_coupon(coupon)

      assert @classroom_repo.has_teacher_toolbox_coupon
    end

    test "returns false when teacher does not have any coupon" do
      refute @classroom_repo.has_teacher_toolbox_coupon
    end

    test "returns false when teacher has a coupon but it is not for toolbox" do
      coupon = create :coupon
      @org.redeem_coupon(coupon)

      refute @classroom_repo.has_teacher_toolbox_coupon
    end
  end

  context "associated attributes" do
    test "reads classroom_name attribute from association correctly" do
      classroom_repo = create :classroom_repository, classroom_name: "Elixir 101"
      classroom_repo.classroom.update(name: "Something Different")
      assert_equal classroom_repo.classroom_name, "Something Different"
    end

    test "reads assignment_name attribute from association correctly" do
      classroom_repo = create :classroom_repository, assignment_name: "Intro to pattern matching"
      classroom_repo.assignment.update(name: "Something Different")
      assert_equal classroom_repo.assignment_name, "Something Different"
    end

    test "reads deadline attribute from association correctly" do
      later = 10.days.from_now.beginning_of_day
      tomorrow = 1.day.from_now.beginning_of_day
      classroom_repo = create :classroom_repository, deadline: later
      classroom_repo.assignment.update(deadline: tomorrow)
      assert_equal classroom_repo.deadline, tomorrow
    end

    test "reads has_autograding attribute from association correctly" do
      classroom_repo = create :classroom_repository, has_autograding: true
      classroom_repo.assignment.update(has_autograding: false)
      refute classroom_repo.has_autograding?
    end

    test "reads admins attribute from association correctly" do
      classroom_repo = create :classroom_repository
      classroom_repo.classroom.instructors << create(:classroom_instructor, login: "octosteve")
      classroom_repo.classroom.instructors << create(:classroom_instructor, login: "jessrudder")
      classroom_repo.classroom.instructors << create(:classroom_instructor, login: "nixpad")
      assert_admins_match("octosteve,jessrudder,nixpad", classroom_repo.admins)
    end
  end

  def assert_admins_match(expected_list, actual_list)
    assert_equal expected_list.split(",").sort, actual_list.split(",").sort
  end
end
