# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvisoryDbEcosystemsAbstractEcosystemRegisterTest < GitHub::TestCase
  class TestRegister < AdvisoryDB::Ecosystems::AbstractEcosystemRegister
    class Registry < AdvisoryDB::Ecosystems::AbstractEcosystemRegistry; end

    def self.registry
      Registry.instance
    end
  end

  setup do
    @subject = TestRegister
    @ecosystem1_slug = :ECOSYSTEM1
    @ecosystem1_name = "ecosystem1"
    @ecosystem1_label = "Ecosystem 1"
    @hydro_enum_value = :ECOSYSTEM_1
    @ecosystem1 = ecosystem(@ecosystem1_name, @ecosystem1_label, @hydro_enum_value)
    @subject.send(:add, @ecosystem1_slug, @ecosystem1)
  end

  teardown do
    @subject.registry.reset!
  end

  test "returns registered ecosystems" do
    assert_kind_of Array, @subject.ecosystems
    assert_equal 1, @subject.ecosystems.size
  end

  test "prevents registering two ecosystems with the same slug" do
    ecosystem2 = ecosystem("ecosystem2", "Ecosystem 2", :ECOSYSTEM2)
    error = assert_raises ArgumentError do
      @subject.send(:add, @ecosystem1_slug, ecosystem2)
    end
    assert_equal "Ecosystem slug is not unique: #{@ecosystem1_slug}",
                error.message
  end

  test "prevents registering two ecosystems with the same name" do
    ecosystem2 = ecosystem(@ecosystem1_name, "Ecosystem 2", :ECOSYSTEM2)
    error = assert_raises ArgumentError do
      @subject.send(:add, :ECOSYSTEM2, ecosystem2)
    end
    assert_equal "Ecosystem name is not unique: #{@ecosystem1_name}",
                error.message
  end

  test "prevents registering two ecosystems with the same label" do
    ecosystem2 = ecosystem("ecosystem2", @ecosystem1_label, :ECOSYSTEM2)
    error = assert_raises ArgumentError do
      @subject.send(:add, :ECOSYSTEM2, ecosystem2)
    end
    assert_equal "Ecosystem label is not unique: #{@ecosystem1_label}",
                error.message
  end

  test "prevents registering two ecosystems with the same hydro_enum_value" do
    ecosystem2 = ecosystem("ecosystem2", "Ecosystem 2", @hydro_enum_value)
    error = assert_raises ArgumentError do
      @subject.send(:add, :ECOSYSTEM2, ecosystem2)
    end
    assert_equal "Ecosystem Hydro enum value is not unique: #{@hydro_enum_value}", error.message
  end

  test "fetches an ecosystem by its slug" do
    assert_equal @ecosystem1, @subject.get(@ecosystem1_slug)
  end

  def ecosystem(name, label, hydro_enum_value)
    attributes = {
      name:,
      description: "",
      label:,
      hydro_enum_value:,
    }
    AdvisoryDB::Ecosystems::EcosystemV2.new(**attributes)
  end
end
