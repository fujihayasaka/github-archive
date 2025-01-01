# typed: true
# frozen_string_literal: true

require "test_helper"

class MoveWork::ChooseResourcesFormTest < GitHub::TestCase
  test "limit the number of projects selected" do
    choose_resources = MoveWork::ChooseResourcesForm.new(repository_ids: [1], project_ids: (MoveWork::ChooseResourcesForm::MAXIMUM_RESOURCE_SELECTION + 1).times.map { |i| i })

    refute choose_resources.valid?
    assert_equal "You can select a maximum of 50 projects", choose_resources.errors[:base].first
  end

  test "limit the number of repositories selected" do
    choose_resources = MoveWork::ChooseResourcesForm.new(project_ids: [1], repository_ids: (MoveWork::ChooseResourcesForm::MAXIMUM_RESOURCE_SELECTION + 1).times.map { |i| i })

    refute choose_resources.valid?
    assert_equal "You can select a maximum of 50 repositories", choose_resources.errors[:base].first
  end
end
