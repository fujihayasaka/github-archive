# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  # Holds all registered setting domains
  # Used to handle event hooks for attribute changes / resource creation
  module DomainRegistry
    Factory = T.type_alias { T.proc.returns(SettingsCoreV2::DomainAccessorBase) }

    @entries = T.let({}, T::Hash[String, Factory])

    sig { params(name: String, factory: Factory).void }
    def self.register(name, &factory)
      @entries[name] = factory
    end

    sig { void }
    def self.clear
      @entries.clear
    end

    sig { returns(T::Hash[String, Factory]) }
    def self.all
      @entries.dup
    end

    sig { params(name: String).returns(T.nilable(Factory)) }
    def self.find(name)
      @entries[name]
    end

    sig { params(resource: T.untyped, actor: T.nilable(User)).void }
    def self.on_resource_create(resource, actor = nil)
      @entries.each do |name, factory|
        domain = factory.call
        domain.known_setting_definitions.each do |definition|
          next unless definition.has_setting_changed_hook?
          next unless definition.applies_to_resource?(resource)
          domain.enqueue_setting_changed_job(definition.setting_name, resource, actor: actor)
        rescue => e
          GitHub.logger.error(
            "settings.on_resource_update.error",
            "gh.settings.domain": name,
            "gh.settings.setting_name": definition.setting_name,
            "gh.settings.error": e.message,
          )
        end
      end
    end

    sig do
      params(
        resource: T.untyped,
        previous_attributes: T::Array[AttributeOverride],
        actor: T.nilable(User),
      ).void
    end
    def self.on_resource_update(resource, previous_attributes, actor = nil)
      @entries.each do |name, factory|
        domain = factory.call
        domain.known_setting_definitions.each do |definition|
          next unless definition.needs_change_propagation?
          next unless definition.resource_definitions.any? do |rd|
            rd.is_resource?(resource) && rd.matchers.any? do |m|
              # `previous_attributes` may carry a sub-attribute suffix, e.g.
              # "repository.custom_properties[prop_name]"; compare against the
              # matcher's base attribute name.
              previous_attributes.any? { |attr| attr.attribute.to_s.split("[", 2).first == m.attribute }
            end
          end

          domain.enqueue_setting_changed_job(
            definition.setting_name,
            resource,
            previous_attributes: previous_attributes,
            actor: actor,
          )
        rescue => e
          GitHub.logger.error(
            "settings.on_resource_update.error",
            "gh.settings.domain": name,
            "gh.settings.setting_name": definition.setting_name,
            "gh.settings.error": e.message,
          )
        end
      end
    end
  end
end
