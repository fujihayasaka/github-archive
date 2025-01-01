# typed: true
# frozen_string_literal: true

# Behavior for JSON-backed settings columns.
# See UserSettings for example use.
module SettingsCollection
  class InvalidUpdate < ArgumentError; end

  BLANK_SETTINGS = {}.freeze

  # Configure a model to store settings in a JSON column.
  # host_model is the AR model class that has a JSON column called `column_name`.
  def self.configure(host_model, column_name: :settings,  &block)
    raise ArgumentError, "want block" unless block_given?

    #validate col

    collection_model = Class.new(::SettingsCollection::CollectionModel)
    host_model.const_set :SettingsCollection, collection_model
    host_model.include(::SettingsCollection::Mixin)
    host_model.settings_collection_class = collection_model
    host_model.settings_column_name = column_name

    # Yield to caller so it can register validators
    collection_model.class_eval(&block)

    # An ActiveModel::Type::Value instance for serialization/deserialization
    column_type = ::SettingsCollection::JsonColumnType.new(collection_model: collection_model)

    host_model.attribute(column_name, column_type, default: BLANK_SETTINGS)

    # Cascade collection validations to the host model instance
    host_model.validate :all_settings_are_valid
  end
end
