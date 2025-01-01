# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroRepositoryPopulateLabelsJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  test "when owned by organization with labels, queues job to create labels owner's user_labels" do
    owner = create(:organization)
    create_list(:user_label, 10, user: owner)
    repo = create(:repository, owner: owner)

    expected_labels = owner.user_labels
    refute_empty expected_labels # sanity check

    message = { repository_id: repo.id }
    perform_hydro_message_job(message, schema: "github.repositories.v1.Created", queue: "hydro_repository_populate_labels")

    expected_labels.each do |user_label|
      label = repo.labels.where(name: user_label.name).first
      refute_nil label, "should have created label '#{user_label.name}'"
      assert_equal user_label.color, T.must(label).color
      assert_equal user_label.description, T.must(label).description
    end

    # sanity check: org-specific labels will differ from the Label default list
    refute_same_elements repo.labels.pluck(:name), Label::DEFAULT_LABEL_NAMES.to_a
  end

  test "when org has no labels, creates no repo labels" do
    owner = create(:organization)
    owner.user_labels.destroy_all

    repo = create(:repository, owner: owner)

    message = { repository_id: repo.id }
    perform_hydro_message_job(message, schema: "github.repositories.v1.Created", queue: "hydro_repository_populate_labels")

    assert_empty repo.labels
  end

  test "when owned by a user creates labels with default labels' name, color, and description" do
    expected_labels = Label.initial_labels
    repo = create(:repository)

    message = { repository_id: repo.id }
    perform_hydro_message_job(message, schema: "github.repositories.v1.Created", queue: "hydro_repository_populate_labels")

    expected_labels.each do |hash|
      label = repo.labels.where(name: hash[:name]).first
      refute_nil label, "should have created label '#{hash[:name]}'"
      assert_equal hash[:color], T.must(label).color
      assert_equal hash[:description], T.must(label).description
    end

    assert_same_elements Label.where(repository_id: repo.id).pluck(:name), Label::DEFAULT_LABEL_NAMES.to_a
  end

  test "creates repo with initial labels" do
    user = create(:user)
    repo = create(:repository, :full_creation, name: "coffee-script", owner: user)

    message = { repository_id: repo.id }
    perform_hydro_message_job(message, schema: "github.repositories.v1.Created", queue: "hydro_repository_populate_labels")

    labels = T.must(repo).labels.map(&:name)
    assert labels.include?("bug")
    assert labels.include?("enhancement")
  end
end
