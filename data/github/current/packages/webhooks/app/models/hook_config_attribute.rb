# typed: true
# frozen_string_literal: true

class HookConfigAttribute < ApplicationRecord::Domain::Hooks
  attribute :value, StringFromBinary.new
  encrypts :value
  validates :value, length: { maximum: 1024 }, presence: true

  # Module which can be used to extend the association proxy in order to
  # provide some serializable-like methods.
  #
  # This allows you to treat the collection as a serialized Hash of config
  # where the keys are key Strings and the values are value Strings.
  # The backing records will be persisted/destroyed when the parent is saved.
  #
  # Example:
  #
  # has_many :config_attribute_records,
  #   :class_name  => "HookConfigAttribute",
  #   :dependent   => :destroy,
  #   :autosave => true,
  #   :extend => HookConfigAttribute::AssociationExtension
  #
  #
  #   instance.config_attribute_records.config_map
  #   # => {"key" => "some_key", "value" => "some_value"}
  #
  #   instance.config_attribute_records.config_map = {
  #       "key" => "some_key"
  #     }
  #   # => {"contents" => :write}
  #   instance.save
  #   instance.config_attribute_records.all
  #     => [#<HookConfigAttribute id: 405, hook_id: 517, key: "url", value: "http://foo.com">]
  #
  module AssociationExtension
    extend T::Helpers
    # Public: Returns config currently assigned to the hook
    # excluding any config key, value pairs which are currently marked for removal.
    #
    # Returns an Hash of resource Strings to permission Symbols.
    def config_map
      active_configs = T.unsafe(self).select { |record| !record.marked_for_destruction? }
      active_configs.each_with_object({}) do |record, memo|
        next unless record.value.present?
        memo[record.key] = record.value
      end
    end

    # Public: Sets the hooks's config. Any existing
    # config key, value pairs not included will be marked for removal and destroyed when
    # the hook is saved.
    #
    # assigned_configs - A Hash of key Strings to value Strings.
    #
    # Returns the assigned config Hash.
    def set_config(assigned_configs, destructive: true)
      assigned_configs = init_assigned_config(assigned_configs)
      existing_configs = config_map
      configs_to_add = assigned_configs.keys - existing_configs.keys
      configs_to_change = existing_configs.keys.select do |resource|
        existing_configs[resource] != assigned_configs[resource]
      end

      add_configs(configs_to_add, assigned_configs)
      if destructive
        configs_to_remove = existing_configs.keys - assigned_configs.keys
        remove_configs(configs_to_remove)
      end
      change_configs(configs_to_change, assigned_configs)

      assigned_configs
    end

    private

    def init_assigned_config(assigned_configs)
      assigned_configs ||= {}

      assigned_configs = assigned_configs.each_with_object({}) do |(k, v), memo|
        memo[k.to_s] = massage_config_value(v)
      end
      assigned_configs.reject! { |_k, v| v.blank? }
      assigned_configs
    end

    def add_configs(configs_to_add, assigned_configs)
      configs_to_add.each do |key|
        T.unsafe(self).build key: key.to_s, value: assigned_configs[key].to_s
      end
    end

    def change_configs(configs_to_change, assigned_configs)
      configs_to_change.each do |key|
        record_to_change = T.unsafe(self).detect { |record| record.key == key }
        record_to_change.value = assigned_configs[key]
      end
    end

    def remove_configs(configs_to_remove)
      configs_to_remove.each do |key|
        record_to_remove = T.unsafe(self).detect { |record| record.key == key }
        record_to_remove.mark_for_destruction
      end
    end

    def massage_config_value(value)
      case value
      when true  then value = "1"
      when false then value = "0"
      end
      value
    end
  end

  belongs_to :hook
  destroy_in_background_with :hook

  # Public: Key for the hook configuration attribute (e.g. "url")
  # column :key

  # Public: Value for the hook configuration attribute (e.g. "https://github.com")
  # column :value
  validates_uniqueness_of :key, scope: :hook_id, case_sensitive: false
end
