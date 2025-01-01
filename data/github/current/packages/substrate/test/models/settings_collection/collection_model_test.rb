# typed: true
# frozen_string_literal: true

require "test_helper"

class SettingsCollectionCollectionModelTest < GitHub::TestCase
  attr_reader :model

  def setup
    @model = Class.new(SettingsCollection::CollectionModel)
    @model.attribute :tab_size, :integer, default: 8
  end

  context "initialization" do
    test "from_json creates a new model object from a string" do
      settings = model.from_json("{\"tab_size\":2}")
      assert_equal 2, settings.tab_size
    end

    test "from_json creates a new model object from a hash" do
      settings = model.from_json({ tab_size: 2 })
      assert_equal 2, settings.tab_size
    end

    test "from_json creates a new model object from a nil, using default attribute values" do
      settings = model.from_json(nil)
      assert_equal 8, settings.tab_size
    end
  end

  context "default values" do
    test "default_value returns the given default value if configured" do
      assert_equal 8, model.default_value(:tab_size)
    end

    test "is_default_value? says if a given value is equal to the configured default value" do
      assert model.is_default_value?(:tab_size, 8)
      assert_not model.is_default_value?(:tab_size, 2)
    end
  end
end
