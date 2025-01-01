# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvisoryDbEcosystemsEcosystemV2Test < GitHub::TestCase
  setup do
    @subject = AdvisoryDB::Ecosystems::EcosystemV2
  end

  test "raises an error if name is not between 2 and 20 characters" do
    err = assert_raises ArgumentError do
      @subject.new(name: "A23456789012345678901", description: "", hydro_enum_value: :ECO)
    end
    assert_equal "Ecosystem name must be 2 - 20 characters in length",
                 err.message

    err = assert_raises ArgumentError do
      @subject.new(name: "A", description: "", hydro_enum_value: :ECO)
    end
    assert_equal "Ecosystem name must be 2 - 20 characters in length",
                 err.message
  end

  test "raises an error if name does not meet character requirements" do
    err = assert_raises ArgumentError do
      @subject.new(name: "A234-5678", description: "", hydro_enum_value: :ECO)
    end
    assert_match(/\AEcosystem name must match format/, err.message)
  end

  test "dependency_graph_supported? is false by default" do
    refute @subject.new(name: "eco", description: "", hydro_enum_value: :ECO).dependency_graph_supported?
    assert @subject.new(name: "eco", description: "", hydro_enum_value: :ECO, dependency_graph_supported: true).dependency_graph_supported?
    refute @subject.new(name: "eco", description: "", hydro_enum_value: :ECO, dependency_graph_supported: false).dependency_graph_supported?
  end

  test "label returns name if not specified" do
    name = "eco"
    label = "Eco System"

    assert_equal label, @subject.new(
      name: name,
      description: "",
      hydro_enum_value: :ECO,
      label: label
    ).label

    assert_equal name, @subject.new(
      name: name,
      description: "",
      hydro_enum_value: :ECO,
      label: nil
    ).label
  end

  test "public? is false by default" do
    refute @subject.new(name: "eco", description: "", hydro_enum_value: :ECO).public?
    assert @subject.new(name: "eco", description: "", hydro_enum_value: :ECO, is_public: true).public?
    refute @subject.new(name: "eco", description: "", hydro_enum_value: :ECO, is_public: false).public?
  end
end
