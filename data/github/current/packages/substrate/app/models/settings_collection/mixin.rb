# typed: true
# frozen_string_literal: true

module SettingsCollection
  # Methods used by the ActiveRecord model to interact with its JSON settings collection column.
  module Mixin
    extend T::Helpers
    requires_ancestor { ApplicationRecord::Base }
    include Kernel

    module ClassMethods
      def settings_owner(fk)
        T.unsafe(self).settings_owner_fk = fk.to_sym
      end
    end

    mixes_in_class_methods(ClassMethods)

    def self.included(base)
      base.class_attribute :settings_collection_class
      base.class_attribute :settings_column_name
      base.class_attribute :settings_owner_fk, default: nil
      base.class.delegate :is_default_value?, :default_value, to: :settings_collection_class
      base.extend(ClassMethods)
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
      set_without_reload!(attr, value)

      reload
      collection_model_instance
    end

    def set_without_reload!(attr, value)
      errors = collection_model_instance.validate_update(attr: attr, value: value)
      if errors.any?
        raise SettingsCollection::InvalidUpdate, "#{attr}: #{errors.full_messages.to_sentence}"
      end

      save_with_race_recovery! { collection_model_instance.public_send(:"#{attr}=", value) }
    end

    # Sets multiple attributes at once and saves in a single write.
    # Accepts a hash of { attr => value } pairs.
    def set_multiple_without_reload!(attrs)
      collection_model_instance.assign_attributes(attrs)

      unless collection_model_instance.valid?
        raise SettingsCollection::InvalidUpdate, collection_model_instance.errors.full_messages.to_sentence
      end

      save_with_race_recovery! { collection_model_instance.assign_attributes(attrs) }
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

    private

    def save_with_race_recovery!
      save!
    rescue ActiveRecord::RecordNotUnique
      raise unless new_record?
      owner_fk = self.class.settings_owner_fk
      raise unless owner_fk
      winner = self.class.find_by!(owner_fk => send(owner_fk))
      self.id = winner.id
      instance_variable_set(:@new_record, false)
      reload
      yield
      save!
    end
  end
end
