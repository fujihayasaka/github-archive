# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvisoryDbEcosystemsAbstractEcosystemRegistryTest < GitHub::TestCase
  class TestRegistry < AdvisoryDB::Ecosystems::AbstractEcosystemRegistry; end
  class SecondTestRegistry < AdvisoryDB::Ecosystems::AbstractEcosystemRegistry; end

  setup do
    @subject = TestRegistry
    @instance = @subject.instance
  end

  teardown do
    @instance.reset!
    SecondTestRegistry.instance.reset!
  end

  test "is a singleton" do
    assert_raises NoMethodError do
      @subject.new
    end
    assert_equal @instance.object_id, @subject.instance.object_id
  end

  test "doesn't pollute across registrars" do
    ecosystem1 = ecosystem("test1", :TEST1)
    ecosystem2 = ecosystem("test2", :TEST2)
    @instance.add(:TEST, ecosystem1)
    SecondTestRegistry.instance.add(:TEST, ecosystem2)
    assert_equal [ecosystem1], @instance.ecosystems
    assert_equal [ecosystem2], SecondTestRegistry.instance.ecosystems
  end

  test "returns registered ecosystems" do
    new_ecosystem = ecosystem("test", :TEST)
    @instance.add(:TEST, new_ecosystem)
    ecosystems = @instance.ecosystems
    assert_equal ecosystems, [new_ecosystem]
  end

  test "prevents registering two ecosystems with the same slug" do
    slug = :TEST_SLUG
    ecosystem1 = ecosystem("test1", :TEST1)
    ecosystem2 = ecosystem("test2", :TEST2)
    @instance.add(slug, ecosystem1)
    error = assert_raises ArgumentError do
      @instance.add(slug, ecosystem2)
    end
    assert_equal "Ecosystem slug is not unique: #{slug}", error.message
  end

  test "prevents registering two ecosystems with the same name" do
    name = "test_name"
    ecosystem1 = ecosystem(name, :TEST1)
    ecosystem2 = ecosystem(name, :TEST2)
    @instance.add(:TEST1, ecosystem1)
    error = assert_raises ArgumentError do
      @instance.add(:TEST2, ecosystem2)
    end
    assert_equal "Ecosystem name is not unique: #{name}", error.message
  end

  test "prevents registering two ecosystems with the same label" do
    label = "test label"
    ecosystem1 = ecosystem("test1", :TEST1, label:)
    ecosystem2 = ecosystem("test2", :TEST2, label:)
    @instance.add(:TEST1, ecosystem1)
    error = assert_raises ArgumentError do
      @instance.add(:TEST2, ecosystem2)
    end
    assert_equal "Ecosystem label is not unique: #{label}", error.message
  end

  test "prevents registering two ecosystems with the same hydro_enum_value" do
    hydro_enum_value = :TEST_HYDRO_ENUM_VALUE
    ecosystem1 = ecosystem("test1", hydro_enum_value)
    ecosystem2 = ecosystem("test2", hydro_enum_value)
    @instance.add(:TEST1, ecosystem1)
    error = assert_raises ArgumentError do
      @instance.add(:TEST2, ecosystem2)
    end
    assert_equal "Ecosystem Hydro enum value is not unique: #{hydro_enum_value}", error.message
  end

  test "fetches an ecosystem by its slug" do
    slug = :TEST
    new_ecosystem = ecosystem("test", :TEST)
    @instance.add(slug, new_ecosystem)
    assert_equal new_ecosystem, @instance.get(slug)
  end

  def ecosystem(name, hydro_enum_value, attributes = {})
    attributes[:name] = name
    attributes[:description] = ""
    attributes[:hydro_enum_value] = hydro_enum_value
    AdvisoryDB::Ecosystems::EcosystemV2.new(**attributes)
  end
end
