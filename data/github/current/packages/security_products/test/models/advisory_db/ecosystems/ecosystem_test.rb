# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvisoryDbEcosystemsEcosystemTest < GitHub::TestCase
  setup do
    @subject = AdvisoryDB::Ecosystems::Ecosystem
  end

  test "raises an error if name is not between 2 and 20 characters" do
    err = assert_raises ArgumentError do
      @subject.new(name: "A23456789012345678901", description: "")
    end
    assert_equal "Ecosystem name must be 2 - 20 characters in length",
                 err.message

    err = assert_raises ArgumentError do
      @subject.new(name: "A", description: "")
    end
    assert_equal "Ecosystem name must be 2 - 20 characters in length",
                 err.message
  end

  test "raises an error if name does not meet character requirements" do
    err = assert_raises ArgumentError do
      @subject.new(name: "A234-5678", description: "")
    end
    assert_match(/\AEcosystem name must match format/, err.message)
  end

  test "is_public is true by default" do
    assert @subject.new(name: "eco", description: "").public?
    assert @subject.new(name: "eco", description: "", is_public: true).public?
    refute @subject.new(name: "eco", description: "", is_public: false).public?
  end

  test "label returns name if not specified" do
    name = "eco"
    label = "Eco System"

    assert_equal label, @subject.new(
      name: name,
      description: "",
      label: label
    ).label

    assert_equal name, @subject.new(
      name: name,
      description: "",
      label: nil
    ).label
  end

  test "purl_type returns name if not specified" do
    name = "eco"
    purl_type = "eco_system"

    assert_equal purl_type, @subject.new(
      name: name,
      description: "",
      purl_type: purl_type
    ).purl_type

    assert_equal name, @subject.new(
      name: name,
      description: "",
      purl_type: nil
    ).purl_type
  end
end
