# typed: true
# frozen_string_literal: true

require "test_helper"

class DeveloperProgramDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @program_membership = create(:developer_program_membership, user: @user)
  end

  context "#show_developer_program_badge?" do
    if GitHub.enterprise?
      test "returns false on GHE" do
        refute_predicate @user, :show_developer_program_badge?
      end
    else
      test "returns true if user is developer program member" do
        assert_predicate @user, :show_developer_program_badge?
      end

      test "returns false if user is not developer program member" do
        refute_predicate create(:user), :show_developer_program_badge?
      end

      test "returns false if user is site admin" do
        staff = create(:staff_admin_user)
        create(:developer_program_membership, user: staff)

        refute_predicate staff, :show_developer_program_badge?
      end

      test "returns false for employee who is not site admin" do
        employee = create(:employee)
        create(:developer_program_membership, user: employee)

        assert_predicate employee, :employee?
        refute_predicate employee, :site_admin?
        refute_predicate employee, :show_developer_program_badge?
      end
    end
  end
end
