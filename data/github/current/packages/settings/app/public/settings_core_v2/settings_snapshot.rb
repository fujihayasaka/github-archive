# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  module SettingsSnapshot
    sig { params(domain: SettingsCoreV2::DomainAccessorBase, resource: T.untyped, settings: T::Array[ISetting]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def self.snapshot_cached_settings(domain, resource, settings)
      return [] unless settings.any? { |s| domain.definition_by_name(s.name)&.needs_change_propagation? }

      current_settings = domain.load_settings({ resource => settings.map(&:name) })
      settings.filter_map do |setting|
        definition = domain.definition_by_name(setting.name)
        next unless definition&.needs_change_propagation?

        resource = setting.resource
        resource = resource.internal_record if resource.respond_to?(:internal_record)
        matching_setting = current_settings.find { |s| s.name == setting.name } || MemorySetting.new(setting.name, nil, resource)

        {
          resource_type: resource.class.name,
          resource_id: resource.respond_to?(:id) ? resource.id : nil,
          setting_name: setting.name,
          old_setting: matching_setting.serialize,
        }
      end
    end
  end
end
