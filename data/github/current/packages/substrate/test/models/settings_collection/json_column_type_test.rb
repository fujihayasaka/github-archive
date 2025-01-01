# typed: true
# frozen_string_literal: true

require "test_helper"
class SettingsCollectionJsonColumnTypeTest < GitHub::TestCase
  attr_reader :type, :model

  def setup
    @model = Class.new(SettingsCollection::CollectionModel)
    @model.attribute :tab_size, :integer, default: 8
    @type = SettingsCollection::JsonColumnType.new(collection_model: @model)
    assert_equal model.attribute_names, ["tab_size"]
  end

  context "cast" do
    test "casts from a json string, ignoring unknown attributes" do
      settings = type.cast("{\"tab_size\":2,\"foo\":12}")
      assert settings.is_a?(model)
      assert_equal 2, settings.tab_size
      assert_not settings.respond_to?(:foo)
    end

    test "hydrates default attributes from an empty json hash" do
      settings = type.cast("{}")
      assert settings.is_a?(model)
      assert_equal 8, settings.tab_size
    end

    test "casts from a hash, ignoring unknown attributes" do
      settings = type.cast({ tab_size: 2, foo: 12 })
      assert settings.is_a?(model)
      assert_equal 2, settings.tab_size
      assert_not settings.respond_to?(:foo)
    end

    test "casts from a model object" do
      existing_settings = model.new(tab_size: 2)
      settings = type.cast(existing_settings)
      assert settings.is_a?(model)
      assert_equal 2, settings.tab_size
    end

    test "casts from nil using default attribute values" do
      settings = type.cast(nil)
      assert settings.is_a?(model)
      assert_equal 8, settings.tab_size
    end

    test "returns nil for other inputs" do
      assert_nil type.cast(42)
    end
  end

  context "serialize" do
    test "encodes the model object as json" do
      settings = model.new(tab_size: 2)
      assert_equal "{\"tab_size\":2}", type.serialize(settings)
    end

    test "if all attributes are defaults, encodes the object as an empty hash" do
      settings = model.new(tab_size: 8)
      assert_equal "{}", type.serialize(settings)
    end
  end
end
