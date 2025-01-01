# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RepositoryPopulateLabelsJobTest < GitHub::TestCase
  include JobTestHelper

  test "should return nil if no repo" do
    repo = create(:repository)
    repo.remove(repo.owner)
    repo.purge

    assert_nil RepositoryPopulateLabelsJob.perform_now(repo.id)
  end

  test "should return nil if owner is not an organization" do
    owner = create(:user)
    repo = create(:repository, owner: owner)

    assert_nil RepositoryPopulateLabelsJob.perform_now(repo.id)
  end

  test "should populate with default labels when owned by a user" do
    expected_labels = Label.initial_labels
    repo = create(:repository)

    RepositoryPopulateLabelsJob.perform_now(repo.id)

    expected_labels.each do |hash|
      label = repo.labels.where(name: hash[:name]).first
      refute_nil label, "should have created label '#{hash[:name]}'"
      assert_equal hash[:color], label.color
      assert_equal hash[:description], label.description
    end

    assert_same_elements repo.reload.labels.pluck(:name), Label::DEFAULT_LABEL_NAMES.to_a
  end

  test "should not raise if a label already exists" do
    expected_labels = Label.initial_labels
    repo = create(:repository)

    Label.any_instance.stubs(:save).raises(ActiveRecord::RecordNotUnique)

    assert_nothing_raised do
      RepositoryPopulateLabelsJob.perform_now(repo.id)
    end
  end

  test "should populate labels from owning organization" do
    owner = create(:organization)
    create_list(:user_label, 10, user: owner)
    repo = create(:repository, owner: owner)

    RepositoryPopulateLabelsJob.perform_now(repo.id)

    owner.user_labels.each do |user_label|
      label = repo.labels.where(name: user_label.name).first
      refute_nil label, "should have created label '#{user_label.name}'"
      assert_equal user_label.color, label.color
      assert_equal user_label.description, label.description
    end
  end

  test "should do nothing when owning organization has no labels" do
    owner = create(:organization)
    owner.user_labels.destroy_all

    repo = create(:repository, owner: owner)

    expected_labels = owner.user_labels
    assert_empty expected_labels

    RepositoryPopulateLabelsJob.perform_now(repo.id)

    assert_empty repo.labels
  end
end
