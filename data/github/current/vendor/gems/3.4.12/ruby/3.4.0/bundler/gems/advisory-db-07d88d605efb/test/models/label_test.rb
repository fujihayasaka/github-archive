# frozen_string_literal: true

require "test_helper"

class LabelTest < ActiveSupport::TestCase
  fixtures do
    @advisory_review = create(:advisory_review)
  end

  test "requires case-insensitive name uniqueness" do
    create(:label, name: "bug")
    label = build(:label, name: "Bug")
    refute_predicate label, :valid?
    assert_predicate label.errors[:name], :present?
  end

  test "name can't have commas" do
    label = build(:label, name: "blah,blah")
    refute_predicate label, :valid?
  end

  test "strips leading/trailing whitespace from name & description" do
    label = build(:label, name: " foo ", description: " bar ")
    assert_predicate label, :valid?
    assert_equal "foo", label.name
    assert_equal "bar", label.description
  end

  test "replaces newlines with spaces in name & description" do
    label = build(:label, name: "f\noo", description: "bar\n")
    assert_predicate label, :valid?
    assert_equal "f oo", label.name
    assert_equal "bar", label.description
  end

  test "must have a six digit hex color" do
    label = build(:label, name: "test", color: "yellow")
    refute_predicate label, :valid?

    label.color = "color=aaaaaa'};([],[][(![]+[]"
    refute_predicate label, :valid?

    label.color = "666666\nfoo"
    refute_predicate label, :valid?

    label.color = "666666\n"
    refute_predicate label, :valid?

    label.color = "666666"
    assert_predicate label, :valid?

    label.color = "c0c0c0"
    assert_predicate label, :valid?
  end

  test "color shorthand is expanded on validation" do
    label = build(:label, name: "test", color: "666")
    assert_predicate label, :valid?
    assert_equal "666666", label.color
  end

  test "scoped by case-insensitive name pattern" do
    create(:label, name: "TODO: research")
    create(:label, name: "TODO: verify")
    create(:label, name: "DONE: ready to publish")

    assert_equal 2, Label.with_name_like("todo").count
  end

  test "label settings are stored as part of label serialization" do
    research_label = create(:label, name: "TODO: research")
    research_label.label_settings.hold_publication = "1"
    research_label.save!
    research_label.reload

    assert research_label.label_settings.hold_publication?
  end
end
