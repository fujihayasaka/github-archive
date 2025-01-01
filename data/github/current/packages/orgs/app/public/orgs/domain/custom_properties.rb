# typed: strict
# frozen_string_literal: true

module Orgs
  class Domain
    class CustomProperties < GH::Domain::Base
      include ::CustomProperties::DomainAccessorBase

      # Public: Enterprise level FF check.
      #
      # If org is provided, it checks if the custom properties feature is enabled for the org's business.
      sig { params(source: ::CustomProperties::IPropertySource).returns(T::Boolean) }
      def feature_enabled?(source)
        if source.is_a? Organization
          FeatureFlag.vexi.enabled?(:custom_properties_for_orgs, source.business, default: false)
        else
          FeatureFlag.vexi.enabled?(:custom_properties_for_orgs, T.cast(source, Business), default: false)
        end
      end

      # Public: Set custom properties for organizations
      #
      # source - Business
      # targets - The organizations to update properties for
      # properties - The properties to set on the targets
      # actor - actor performing the update
      sig do
        override.params(
          source: ::CustomProperties::PropertySource,
          targets: T::Array[::CustomPropertiesCore::IPropertyTarget],
          properties: T::Hash[String, ::CustomProperties::PropertyValue],
          actor: T.nilable(Organization::PermissionsDependency::AuthzdActor),
        ).void
      end
      def set_properties_for(source, targets, properties, actor: nil)
        targets.each { |target| assert_org_business_matches_source!(source, T.cast(target, Organization)) }
        check_edit_permissions!(actor, T.cast(source, Business), T.cast(targets, T::Array[Organization]), properties)
        super(source, targets, properties)
      end

      # Public: Retrieve custom properties for given organizations
      #
      # targets - List of organizations to retrieve properties for
      # value_to_use - :manual or :effective values
      # strip_nils - If true, will remove nil values from the properties hashes
      #
      # Returns a hash of target to a hash of property name to value
      sig do
        override
          .type_parameters(:T)
          .params(
            targets: T::Enumerable[T.all(T.type_parameter(:T), ::CustomPropertiesCore::IPropertyTarget)],
            value_to_use: Symbol,
            strip_nils: T::Boolean
          )
          .returns(T::Hash[T.type_parameter(:T), T::Hash[String, T.nilable(::CustomProperties::PropertyValue)]])
          .checked(:always).on_failure(:raise)
      end
      def values_for_targets(targets, value_to_use:, strip_nils: false)
        targets.each { |target| assert_org_belongs_to_business!(T.cast(target, Organization)) }
        super(targets, value_to_use: value_to_use, strip_nils: strip_nils)
      end

      # Public: Retrieve effective custom properties for single organization
      #
      # target - The organization to retrieve properties for
      #
      # Returns a hash of target to a hash of property name to value
      sig { params(target: Organization).returns(T::Hash[String, T.nilable(::CustomProperties::PropertyValue)]) }
      def effective_values_for_org(target)
        values_by_orgs = Orgs.domain.custom_properties.values_for_targets([target], value_to_use: :effective, strip_nils: false)
        values_by_orgs[target] || {}
      end

      # Public: Handles removing an organization target from the business.
      sig { override.params(business: Business, org: Organization).void }
      def handle_org_removed_from_business(business:, org:)
        destroy_all_property_values(org)
      end

      # Public: Add or replace the definition of a custom property for the collection's enterprise.
      #
      # property_name - Property name to define
      # value_type - Type of the property value. One of ["string", "single_select", "multi_select", "true_false"]. Defaults to "string".
      # required - Whether the property is required or not. Defaults to false.
      # default_value - Default value for the property. Defaults to nil. Must be provided if required is true.
      # description - Description of the property. Defaults to nil.
      # allowed_values - Allowed values for the property. Defaults to nil.
      # values_editable_by - Who can edit the values of the property. One of ["enterprise_actors", "enterprise_and_org_actors"]. Defaults to "enterprise_actors".
      #
      # Returns the definition model
      sig do
        override.params(
          source: ::CustomProperties::PropertySource,
          property_name: String,
          value_type: String,
          required: T::Boolean,
          default_value: T.nilable(::CustomProperties::PropertyValue),
          description: T.nilable(String),
          allowed_values: T.nilable(T::Array[String]),
          values_editable_by: T.nilable(String),
          regex: T.nilable(String),
        ).returns(::CustomProperties::IPropertyDefinition)
      end
      def save_definition(source, property_name:, value_type: "string", required: false, default_value: nil, description: nil, allowed_values: nil, values_editable_by: "enterprise_actors", regex: nil) # rubocop:disable Metrics/MethodLength
        result = super(
          source,
          property_name: property_name,
          value_type: value_type,
          required: required,
          default_value: default_value,
          description: description,
          allowed_values: allowed_values,
          values_editable_by: values_editable_by,
          regex: regex
        )

        result
      end

      # Public: Check if the definition is editable by org and org actors
      #
      # definition - The property definition to check
      #
      # Returns true if the definition is editable by org actors, false otherwise
      sig { params(definition: ::CustomProperties::IPropertyDefinition).returns(T::Boolean) }
      def editable_by_org_actors?(definition)
        T.cast(definition, OrganizationCustomPropertyDefinition).enterprise_and_org_actors?
      end

      private

      sig do
        params(
         actor: T.nilable(Organization::PermissionsDependency::AuthzdActor),
         business: Business,
         orgs: T::Array[Organization],
         properties: T::Hash[String, ::CustomProperties::PropertyValue],
       ).void
      end
      def check_edit_permissions!(actor, business, orgs, properties) # rubocop:disable Metrics/MethodLength
        raise EditPropertyPermissionError.new("Actor doesn't have permissions to edit properties") unless actor

        return if actor_has_enterprise_level_permissions?(business, actor)

        editable_properties = properties.filter_map do |property_name, _|
          definition = get_definition(business, property_name)
          next unless definition

          property_name if editable_by_org_actors?(definition)
        end

        enterprise_actors_only = properties.keys - editable_properties
        if enterprise_actors_only.any?
          raise EditPropertyPermissionError.new("Actor doesn't have permissions to edit properties [#{enterprise_actors_only.join(", ")}]")
        end

        orgs_permissions = Promise.all(orgs.map { |org| org.async_can_edit_custom_properties_for_organizations_as_org_actor?(actor) }).sync
        orgs.zip(orgs_permissions).each do |org, org_permission|
          if !org_permission
            raise EditPropertyPermissionError.new("Actor doesn't have permissions to edit properties on organization '#{org.display_login}'")
          end
        end
      end

      sig { params(business: Business, actor: Authz::SorbetTypes::Actor).returns(T::Boolean) }
      def actor_has_enterprise_level_permissions?(business, actor)
        Authz.domain.check_allowed(actor, :edit_enterprise_custom_properties_for_organizations, business)
      end

      sig { override.returns(::CustomPropertiesCore::ICustomPropertiesConfig) }
      def config
        @config ||= T.let(OrganizationPropertiesConfig.new, T.nilable(::CustomPropertiesCore::ICustomPropertiesConfig))
      end

      sig { params(source: ::CustomProperties::PropertySource, org: Organization).void }
      def assert_org_business_matches_source!(source, org)
        assert_org_belongs_to_business!(org)
        raise ArgumentError, "Source must be a Business" unless source.is_a?(Business)
        raise ArgumentError, "Organization '#{org.display_login}' must belong to '#{source.name}'" unless org.business == source
      end

      sig { params(org: Organization).void }
      def assert_org_belongs_to_business!(org)
        raise ArgumentError, "Organization '#{org.display_login}' must belong to a business" unless org.business
      end

      sig { override.params(business: Business, org: Organization).void }
      def handle_org_added_to_business(business:, org:)
        raise NotImplementedError
      end
    end
  end
end
