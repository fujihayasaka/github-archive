# typed: true
# frozen_string_literal: true

module SettingsCollection
  # Methods used by the ActiveRecord model to interact with its JSON settings collection column.
  module Mixin
    extend T::Helpers
    requires_ancestor { ApplicationRecord::Base }
    include Kernel

    def self.included(base)
      base.class_attribute :settings_collection_class
      base.class_attribute :settings_column_name
      base.class.delegate :is_default_value?, :default_value, to: :settings_collection_class
    end

    def settings_collection_class
      self.class.settings_collection_class
    end

    def settings_column_name
      self.class.settings_column_name
    end

    def get(attr)
      raise ArgumentError, "attr must be an attribute of #{settings_collection_class.name}" unless settings_collection_class.has_attribute?(attr)
      collection_model_instance.public_send(attr)
    end

    def set!(attr, value)
      errors = collection_model_instance.validate_update(attr: attr, value: value)
      if errors.any?
        raise SettingsCollection::InvalidUpdate, "#{attr}: #{errors.full_messages.to_sentence}"
      end

      save!
      reload
      collection_model_instance
    end

    # Returns the instance of the generated <host model>::SettingsCollection
    # class that represents the settings in memory.
    def collection_model_instance
      public_send(settings_column_name)
    end

    # Validator that bubbles column validation errors up to the model
    def all_settings_are_valid
      setting_collection = collection_model_instance
      if !setting_collection.valid?
        errors.add(settings_column_name, "is invalid: #{setting_collection.errors.full_messages.to_sentence}")
      end
    end
  end
end
