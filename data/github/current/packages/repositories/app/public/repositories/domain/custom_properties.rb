# typed: strict
# frozen_string_literal: true

module Repositories
  class Domain
    class CustomProperties < GH::Domain::Base
      include CustomPropertiesCore::DomainAccessorBase
      include CustomPropertiesCore::ExternalProperties::DomainAccessorExtension
      include CustomPropertiesCore::SystemProperties::DomainAccessorExtension
      include CustomPropertiesCore::Usages::DomainAccessorExtension

      AuthzdActor = T.type_alias do
        T.any(
          User,
          OrganizationProgrammaticAccessGrant,
          UserProgrammaticAccessGrant,
          IntegrationInstallation,
          ScopedIntegrationInstallation,
          SiteScopedIntegrationInstallation)
      end

      # This method provides a shortcut for the cases when we only need to get key value pairs for each repo.
      # It returns a hash of property values for each repo.
      #
      # repos - repos objects
      # value_to_use - One of `:manual` or `:effective`
      # strip_nils - If true (defaults to false), any properties with a nil value will be completely stripped from the
      #   returned hash
      sig do
        params(
          repos: T::Enumerable[IRepository],
          value_to_use: Symbol,
          strip_nils: T::Boolean
        ).returns(T::Hash[IRepository, T::Hash[String, T.nilable(CustomPropertiesCore::PropertyValue)]]).checked(:always).on_failure(:raise)
      end
      def repo_properties(repos, value_to_use, strip_nils: false)
        check_repos_owner!(repos)
        values_for_targets(repos, value_to_use:, strip_nils:)
      end

      # This method provides a shortcut for the cases when we only need to get key value pairs for each repo.
      # It returns a hash of system property values for each repo.
      #
      # repos - repos objects
      # strip_nils - If true (defaults to false), any properties with a nil value will be completely stripped from the
      #   returned hash
      sig do
        params(
          repos: T::Enumerable[IRepository],
          strip_nils: T::Boolean
        ).returns(T::Hash[IRepository, T::Hash[String, T.nilable(CustomPropertiesCore::PropertyValue)]]).checked(:always).on_failure(:raise)
      end
      def repo_system_properties(repos, strip_nils: false)
        check_repos_owner!(repos)

        # We do not have a scenario for :manual system values so we can default to :effective here
        repos_hash = system_property_values_for_targets(repos, value_to_use: :effective, strip_nils: strip_nils)

        # runtime-risk is included in system_property_definitions for validation purposes,
        # but should only be visible in results when its FF is enabled for the repo's org.
        # Evaluate the flag once per distinct org rather than once per repo to avoid redundant checks.
        runtime_risk_enabled_by_org = T.let(
          repos.map { |repo| T.cast(repo.owner, Organization) }.uniq
            .to_h { |org| [org, runtime_risk_system_property_enabled?(org)] },
          T::Hash[Organization, T::Boolean]
        )

        repos_hash.each do |repo, properties|
          properties.delete("runtime-risk") unless runtime_risk_enabled_by_org[T.cast(repo.owner, Organization)]
        end

        repos_hash
      end

      # This method provides a shortcut for the cases when we only need to get key value pairs for each repo.
      # It returns a hash of external property values for each repo by namespace.
      #
      # repos - repos objects
      # namespace_id - the namespace to filter properties by. If nil, properties from all namespaces will be returned.
      # strip_nils - If true (defaults to false), any properties with a nil value will be completely stripped from the
      #   returned hash
      sig do
        params(
          repos: T::Enumerable[IRepository],
          namespace_id: T.nilable(Integer),
          strip_nils: T::Boolean
        )
        .returns(T::Hash[IRepository, T::Hash[String, T::Hash[String, T.nilable(String)]]])
        .checked(:always).on_failure(:raise)
      end
      def repo_external_properties(repos, namespace_id: nil, strip_nils: false)
        check_repos_owner!(repos)
        external_property_values_for_targets(repos, namespace_id:, strip_nils:)
      end

      # Public: Returns whether the given user can see property definitions for the given source.
      #
      # user - The user to check permissions for
      # source - The source to check permissions for, either an Organization or a Business
      # cap_filter - Optional conditional access filter. When provided and source is an
      #   Organization, checks that the user has satisfied conditional access policies for
      #   that org (e.g. SSO).
      sig do
        params(
          user: AuthzdActor,
          source: CustomPropertiesCore::PropertySource,
          cap_filter: T.nilable(ConditionalAccess::Filter)
        ).returns(T::Boolean)
        .checked(:always).on_failure(:raise)
      end
      def can_see_property_definitions?(user, source, cap_filter = nil)
        has_permission = if user.can_have_granular_permissions?
          resource = source.is_a?(Organization) ? source.resources.organization_custom_properties : source.resources.enterprise_custom_properties
          resource.readable_by?(user)
        else
          source.is_a?(Organization) ? source.member?(user) : source.readable_by?(user)
        end

        return false unless has_permission
        return true unless cap_filter && source.is_a?(Organization)

        cap_filter.unauthorized_resources([source]).empty?
      end

      # Returns whether the provided real user has the necessary permissions at to edit properties at each level.
      # `true` will be returned for both levels for users with the org-level FGP, and users with the repo-level FGP
      # will only have `true` returned for the repo level. Does not take into account whether an individual definition
      # allows repo-level editing, that must be manually checked per definition.
      sig do
        params(user: AuthzdActor, repo: Repository)
        .returns(Repositories::CustomProperties::UserEditPermissions)
        .checked(:always).on_failure(:raise)
      end
      def user_edit_permissions(user, repo)
        return Repositories::CustomProperties::UserEditPermissions.new(org: false, repo: false) unless repo.owner&.organization?

        # if the above statement doesn't return, then we know it's a non-nil organization
        owner = T.cast(repo.owner, Organization)

        org_level, repo_level = Promise.all([
          owner.async_can_edit_organization_custom_properties_values?(user),
          repo.async_can_edit_custom_property_values_as_repo_actor?(user),
        ]).sync

        Repositories::CustomProperties::UserEditPermissions.new(org: org_level, repo: repo_level)
      end

      # Public: Delete all properties for a given entity and source
      #
      # entity - The entity to delete properties for
      # source - The source to delete properties for
      sig { params(entity: ::Repository, source: CustomPropertiesCore::PropertySource).void.checked(:always).on_failure(:raise) }
      def destroy_property_values(entity, source)
        definition_ids = CustomPropertyDefinition.defined_by(source).pluck(:id)
        CustomPropertyValue.where(target_id: entity.id, definition_id: definition_ids).destroy_all
      end

      # Public: Add or replace the definition of a custom property for the collection's org
      #
      # property_name - Property name to define
      # value_type - Type of the property value. One of ["string", "single_select", "multi_select", "true_false"]. Defaults to "string".
      # required - Whether the property is required or not. Defaults to false.
      # default_value - Default value for the property. Defaults to nil. Must be provided if required is true.
      # description - Description of the property. Defaults to nil.
      # allowed_values - Allowed values for the property. Defaults to nil.
      # values_editable_by - Who can edit the values of the property. One of ["org_actors", "org_and_repo_actors"]. Defaults to "org_actors".
      # require_explicit_values - Whether the property requires explicit values. Defaults to false.
      #
      # Returns the definition model
      sig do
        override.params(
          source: CustomPropertiesCore::PropertySource,
          property_name: String,
          value_type: String,
          required: T::Boolean,
          default_value: T.nilable(CustomPropertiesCore::PropertyValue),
          description: T.nilable(String),
          allowed_values: T.nilable(T::Array[String]),
          values_editable_by: T.nilable(String),
          regex: T.nilable(String),
          require_explicit_values: T::Boolean,
        ).returns(CustomPropertiesCore::IPropertyDefinition)
      end
      def save_definition(source, property_name:, value_type: "string", required: false, default_value: nil, description: nil, allowed_values: nil, values_editable_by: "org_actors", regex: nil, require_explicit_values: false)
        existing_definition = get_definition(source, property_name)
        should_reindex = if existing_definition
          existing_definition.required != required || existing_definition.default_value != default_value
        else
          required
        end

        result = persist_definition(
          source,
          property_name: property_name,
          value_type: value_type,
          required: required,
          default_value: default_value,
          description: description,
          allowed_values: allowed_values,
          values_editable_by: values_editable_by,
          regex: regex,
          property_config: { require_explicit_values: require_explicit_values }
        )

        reindex_source_repos(source) if should_reindex
        result
      end

      # Public: Delete definition
      #
      # reindex_source_repos - Optional param. Default true to reindex all repositories in the source after deleting
      #                         the definition. False is used by jobs that delete definitions in bulk which handle a
      #                         bulk reindex afterwards.
      #
      # Returns the deleted definition or nil if it did not exist
      sig do
        override.params(
          source: CustomPropertiesCore::PropertySource,
          property_name: String,
          reindex_source_repos: T::Boolean
        ).returns(T.nilable(CustomPropertiesCore::IPropertyDefinition))
      end
      def delete_definition(source, property_name, reindex_source_repos: true)
        result = super(source, property_name)

        reindex_source_repos(source) if reindex_source_repos
        result
      end

      # Public: Promote a property definition from an organization to the enterprise level.
      #
      # Promotion requires using business level definitions manager.
      # Property can be promoted only if there are no other properties with the same name in the enterprise orgs.
      #
      # definition - Org level property definition to promote
      # Returns promoted property definition
      sig { override.params(business: ::Business, definition: CustomPropertiesCore::IPropertyDefinition).returns(CustomPropertiesCore::IPropertyDefinition) }
      def promote_definition(business, definition)
        result = super(business, definition)

        reindex_source_repos(business) if definition.required
        result
      end

      # Public: Set custom properties for repository targets
      #
      # source - Organization or Business
      # targets - The repository targets to update properties for
      # properties - The properties to set on the targets
      # actor - The actor performing the operation (optional)
      sig do
        override.params(
          source: CustomPropertiesCore::PropertySource,
          targets: T::Array[CustomPropertiesCore::IPropertyTarget],
          properties: T::Hash[String, T.nilable(CustomPropertiesCore::PropertyValue)],
          actor: T.nilable(AuthzdActor),
        ).void
      end
      def set_properties_for(source, targets, properties, actor: nil)
        raise EditPropertyPermissionError.new("Actors can only edit properties for organization source") unless source.is_a?(Organization)

        targets = T.cast(targets, T::Array[IRepository])

        editable_definitions = check_edit_permissions!(source, actor, targets, properties)

        if explicitly_required_definitions(editable_definitions).any?
          errors = validate_explicitly_required_values(editable_definitions, properties, list_property_names_with_assigned_values_for(editable_definitions, targets))
          raise CustomPropertiesCore::Errors::PropertyValidationError.new(errors) if errors.any?
        end

        super(source, targets, properties)

        reindex_repos(targets)
      end

      # Public: Set system properties for repository targets
      #
      # targets - the repos to set the properties for
      # properties - a hash of system property names to their values to set
      sig do
        params(
          targets: T::Array[CustomPropertiesCore::IPropertyTarget],
          properties: T::Hash[String, T.nilable(CustomPropertiesCore::PropertyValue)],
        ).void.checked(:always).on_failure(:raise)
      end
      def set_system_properties_for(targets, properties)
        targets = T.cast(targets, T::Array[IRepository])
        check_repos_owner!(targets)
        super(targets, properties)
        reindex_repos(targets)
      end

      # Public: Combine manual values with the schema default values
      # to produce a hash of effective values
      # It allows in-memory evaluation without saving new values or the would-be new repo.
      sig { params(source: CustomPropertiesCore::PropertySource, manual_values: T::Hash[String, CustomPropertiesCore::PropertyValue]).returns(T::Hash[String, T.nilable(CustomPropertiesCore::PropertyValue)]) }
      def get_effective_values(source, manual_values)
        manual_values = manual_values.reject { |_, value| value.empty? }

        get_definitions(source).to_h do |defn|
          [defn.property_name, manual_values.fetch(defn.property_name, defn.default_value)]
        end
      end

      # Public: Validate properties when creating a new repository in an organization.
      # This method checks if the actor has permissions to set the provided properties
      # and validates the properties against the schema.
      #
      # org - The organization where the repository is being created
      # properties - A hash of properties to validate
      # actor - The actor performing the operation
      #
      # Returns an array of errors. Empty array means that properties are valid.
      sig do
        params(
          org: Organization,
          properties: T.nilable(T::Hash[T.any(String, Symbol), T.untyped]),
          actor: AuthzdActor,
        ).returns(T::Array[T.any(SchemaValidationError, EditPropertyPermissionError)])
      end
      def validate_properties_on_repo_creation(org, properties, actor:) # rubocop:disable Metrics/MethodLength
        properties ||= {}

        org_level_permission = org.can_edit_organization_custom_properties_values?(actor)
        editable_definitions = get_definitions(org)

        unless org_level_permission
          editable_definitions = editable_definitions.select { |definition| editable_by_repo_actors?(definition) }
          editable_property_names_set = editable_definitions.map(&:property_name).map(&:downcase).to_set

          disallowed_properties = properties.stringify_keys.keys.reject do |property_name|
            editable_property_names_set.include?(property_name.downcase)
          end

          if disallowed_properties.any?
            return [EditPropertyPermissionError.new("User does not have permission to set custom properties: #{disallowed_properties.join(', ')}")]
          end
        end

        validation_errors = validate_properties(org, properties)
        if explicitly_required_definitions(editable_definitions).any?
          # On repo creation no properties are set yet, so we pass an empty array for properties_with_set_values
          validation_errors += validate_explicitly_required_values(editable_definitions, properties.stringify_keys, [])
        end

        validation_errors
      end

      # Public: Validate properties when transferring a repository to a new organization.
      # This method checks if the actor has permissions to set the provided properties
      # in the target organization and validates the properties against the schema.
      #
      # repo - Repo being transferred
      # target_owner - The organization where the repository is being transferred to
      # properties - A hash of properties to validate
      # actor - The actor performing the operation
      #
      # Returns an array of errors. Empty array means that properties are valid.
      sig do
        params(
          repo: Repository,
          target_owner: Organization,
          properties: T::Hash[T.any(String, Symbol), T.untyped],
          actor: AuthzdActor,
        ).returns(T::Array[T.any(SchemaValidationError, EditPropertyPermissionError)])
      end
      def validate_properties_on_repo_transfer(repo, target_owner, properties, actor:) # rubocop:disable Metrics/MethodLength
        has_permissions = target_owner.can_edit_organization_custom_properties_values?(actor)
        return [] if !has_permissions && properties.empty?
        return [EditPropertyPermissionError.new("User does not have permission to set custom properties")] if !has_permissions && properties.any?

        same_business_transfer = repo.owner&.business.present? && target_owner.business.present? && repo.owner&.business == target_owner.business

        editable_definitions = get_definitions(target_owner)
        validation_errors = validate_properties(target_owner, properties)
        if explicitly_required_definitions(editable_definitions).any?
          properties_with_set_values = if same_business_transfer
            editable_enterprise_level_definitions = editable_definitions.select(&:business_source_type?)
            list_property_names_with_assigned_values_for(editable_enterprise_level_definitions, [repo])
          else
            []
          end
          validation_errors += validate_explicitly_required_values(editable_definitions, properties.stringify_keys, properties_with_set_values)
        end

        validation_errors
      end

      # Public: Handle the case when an organization is removed from a business.
      #
      # This method kicks off a job to destroy all repository custom property values for the provided
      # business's definitions for all repos in the provded org.
      #
      # business - The business that the organization was removed from
      # org - The organization that was removed from the business
      sig { override.params(business: ::Business, org: ::Organization).void }
      def handle_org_removed_from_business(business:, org:)
        RepositoryCustomPropertiesOrgRemovedFromBusinessJob.perform_later(business: business, org: org)
      end

      # Public: Handle the case when an organization is added to a business.
      #
      # This method kicks off a job to delete any definitions in the organization that conflict by name with
      # the definitions in the business, as those now take precedence.
      #
      # business - The business that the organization was added to
      # org - The organization that was added to the business
      sig { override.params(business: ::Business, org: ::Organization).void }
      def handle_org_added_to_business(business:, org:)
        RepositoryCustomPropertiesOrgAddedToBusinessJob.perform_later(business: business, org: org)
      end

      # Public: Check if the definition is editable by org and repo actors
      #
      # definition - The property definition to check
      #
      # Returns true if the definition is editable by repo actors, false otherwise
      sig { params(definition: CustomPropertiesCore::IPropertyDefinition).returns(T::Boolean) }
      def editable_by_repo_actors?(definition)
        T.cast(definition, CustomPropertyDefinition).org_and_repo_actors?
      end

      # Checks the edit permissions for a given actor, repositories, and properties.
      #
      # source - the source of the properties, must be an Organization
      # actor - the actor for whom the permissions are checked
      # repos - the repositories to check permissions for
      # properties - the properties actor tries to set
      # Raises EditPropertyPermissionError if actor doesn't have permission to edit the properties
      #
      # Returns list of definitions editable by actor
      sig do
        params(
          source: Organization,
          actor: T.nilable(AuthzdActor),
          repos: T::Array[IRepository],
          properties: T::Hash[String, T.untyped]
        )
        .returns(T::Array[CustomPropertiesCore::IPropertyDefinition])
        .checked(:always).on_failure(:raise)
      end
      def check_edit_permissions!(source, actor, repos, properties) # rubocop:disable Metrics/MethodLength
        # nilable actors are temporarily allowed but thrown here for backwards compatibility
        raise EditPropertyPermissionError.new("Actor doesn't have permissions to edit properties") unless actor

        repos.each { |repo| assert_owner_is_this_org!(repo, source) }

        org_permission, *repos_permissions = Promise.all([
          source.async_can_edit_organization_custom_properties_values?(actor),
          *repos.map { |repo| T.cast(repo, Repository).async_can_edit_custom_property_values_as_repo_actor?(actor) } # rubocop:disable GitHub/AvoidCast
        ]).sync

        definitions = T.cast(get_definitions(source), T::Array[CustomPropertyDefinition])

        return definitions if org_permission

        editable_properties = properties.filter_map do |property_name, _|
          definition = get_definition(source, property_name)
          next unless definition

          property_name if editable_by_repo_actors?(definition)
        end

        org_actor_only_properties = properties.keys - editable_properties
        if org_actor_only_properties.any?
          raise EditPropertyPermissionError.new("Actor doesn't have permissions to edit properties [#{org_actor_only_properties.join(", ")}]")
        end

        repos.zip(repos_permissions).each do |repo, repo_permission|
          if !repo_permission
            raise EditPropertyPermissionError.new("Actor doesn't have permissions to edit properties on repo '#{repo.name}'")
          end
        end

        definitions.select(&:org_and_repo_actors?)
      end

      # Public: Returns the system property definitions for repositories.
      #
      # These definitions are the source of truth for deployment-related system properties
      # (e.g. "deployable", "deployed", "runtime-risk")
      #
      # Returns an array of Definition objects.
      sig { override.returns(T::Array[CustomPropertiesCore::SystemProperties::Definition]) }
      def system_property_definitions
        @system_property_definitions ||= T.let(
          [
            CustomPropertiesCore::SystemProperties::Definition.new(
              config: config,
              property_name: "deployable",
              value_type: "true_false",
              description: "Deployable repositories have produced an artifact which is stored in an artifact registry according to the GitHub virtual registry."
            ).freeze,
            CustomPropertiesCore::SystemProperties::Definition.new(
              config: config,
              property_name: "deployed",
              value_type: "true_false",
              description: "Deployed repositories have an actively deployed artifact according to the GitHub virtual registry."
            ).freeze,
            CustomPropertiesCore::SystemProperties::Definition.new(
              config: config,
              property_name: "runtime-risk",
              value_type: "multi_select",
              allowed_values: %w[critical-resource internet-exposed lateral-movement sensitive-data],
              description: "Runtime risk labels associated with actively deployed artifacts according to the GitHub virtual registry."
            ).freeze,
          ], T.nilable(T::Array[CustomPropertiesCore::SystemProperties::Definition])
        )
      end

      # Returns whether external properties are enabled for a given source
      sig { params(source: CustomPropertiesCore::IPropertySource).returns(T::Boolean) }
      def external_properties_enabled?(source)
        if source.is_a?(Orgs::IOrganization)
          FeatureFlag.vexi.enabled?(:external_properties_for_repositories, source, source.business, default: false)
        else
          FeatureFlag.vexi.enabled?(:external_properties_for_repositories, source, default: false)
        end
      end

      # Public: Delete all external property definitions for a given source and integration installation.
      #
      # source                   - The organization or business that owns the definitions
      # integration_installation - The integration installation to delete definitions for
      sig { params(source: CustomPropertiesCore::PropertySource, integration_installation: IntegrationInstallation).void }
      def destroy_all_external_properties_for_integration(source, integration_installation)
        super(source, integration_installation)

        reindex_source_repos(source)
      end

      # Public: Set external property values for repository targets.
      #
      # integration_installation - The integration installation authorized to update the properties
      # targets      - The repository targets to update properties for
      # properties   - A hash of property names to string values (nil to delete)
      # namespace_id - The namespace to scope definitions to
      sig do
        override.params(
          integration_installation: IntegrationInstallation,
          targets: T::Array[CustomPropertiesCore::IPropertyTarget],
          properties: T::Hash[String, T.nilable(String)],
        ).void.checked(:always).on_failure(:raise)
      end
      def set_external_properties_for(integration_installation, targets, properties)
        targets = T.cast(targets, T::Array[IRepository])
        check_repos_owner!(targets)

        super(integration_installation, targets, properties)

        reindex_repos(targets)
      end

      private

      # Validate that all property definitions requiring explicit values have values provided.
      #
      # This method checks whether properties marked with `require_explicit_values` have been
      # explicitly set in the provided properties hash. Properties that require explicit values
      # cannot rely on default values and must be provided by the user.
      #
      # editable_definitions - Array of property definitions that the user can edit
      # properties - Hash of property names to values that are being set
      # properties_with_set_values - Array of property names that currently have values set
      #
      # Returns an array of SchemaValidationError objects for any definitions that require
      #         explicit values but were not provided in the properties hash. Returns an empty
      #         array if all required properties are present.
      sig do
        params(
          editable_definitions: T::Array[CustomPropertiesCore::IPropertyDefinition],
          properties: T::Hash[String, T.untyped],
          properties_with_set_values: T::Array[String],
        ).returns(T::Array[CustomPropertiesCore::Errors::SchemaValidationError])
      end
      def validate_explicitly_required_values(editable_definitions, properties, properties_with_set_values) # rubocop:disable Metrics/MethodLength
        definitions_requiring_explicit_value = explicitly_required_definitions(editable_definitions)

        # Calculate what properties will have values set by the end of the operation
        properties_with_set_values = properties_with_set_values.map(&:downcase).to_set
        properties.each do |property_name, value|
          property_name = property_name.downcase
          next properties_with_set_values.add(property_name) if value.present?
          properties_with_set_values.delete(property_name)
        end

        definitions_missing_values = definitions_requiring_explicit_value.reject do |definition|
          properties_with_set_values.include?(definition.property_name.downcase)
        end

        return [] if definitions_missing_values.empty?

        errors = definitions_missing_values.map do |definition|
          CustomPropertiesCore::Errors::SchemaValidationError.new(definition.property_name, "Property '#{definition.property_name}' requires an explicit value to be set")
        end

        errors
      end

      sig { override.returns(CustomPropertiesCore::ICustomPropertiesConfig) }
      def config
        @config ||= T.let(RepoPropertiesConfig.new, T.nilable(CustomPropertiesCore::ICustomPropertiesConfig))
      end

      sig { params(source: CustomPropertiesCore::PropertySource).void }
      def reindex_source_repos(source)
        if source.is_a?(::Business)
          BulkReposIndexJob.reindex_business(source)
        else
          BulkReposIndexJob.reindex_org(source.id)
        end
      end

      sig { params(repos: T::Enumerable[IRepository]).void }
      def reindex_repos(repos)
        repos.each do |repo|
          Search.add_to_search_index("repository", repo.id)
        end
      end

      sig { params(repos: T::Enumerable[IRepository]).void }
      def check_repos_owner!(repos)
        repos.each do |repo|
          raise ArgumentError, "all repos must belong to an organization" unless repo.owner&.organization?
        end
      end

      sig { params(repo: IRepository, source: Organization).void.checked(:always).on_failure(:raise) }
      def assert_owner_is_this_org!(repo, source)
        repo_org = T.cast(repo.owner, ::Organization)
        raise ArgumentError, "Invalid entity: repo #{repo} doesn't belong to org #{source}" unless repo_org == source
      end

      # Returns names of properties that are set for all of the provided targets
      sig { params(definitions: T::Array[CustomPropertiesCore::IPropertyDefinition], targets: T::Array[CustomPropertiesCore::IPropertyTarget]).returns(T::Array[String]) }
      def list_property_names_with_assigned_values_for(definitions, targets)
        return [] if definitions.empty? || targets.empty?

        definitions_by_id = T.let(definitions.index_by(&:id), T::Hash[Integer, CustomPropertiesCore::IPropertyDefinition])

        target_ids = targets.map(&:properties_target_id)
        values_by_target_id = CustomPropertyValue
          .where(target_id: target_ids, definition_id: definitions.map(&:id))
          .group_by(&:target_id)

        # Ensure all target IDs are present in the hash, even if they have no values
        values_by_target_id = target_ids.index_with { |id| values_by_target_id.fetch(id, []) }

        # Create a single list of definitions ids that are present for every target.
        definition_ids_with_assigned_values = values_by_target_id.values
          .map { |values| values.map(&:definition_id) }
          .reduce { |common_definition_ids, definition_ids| common_definition_ids & definition_ids }

        definition_ids_with_assigned_values.filter_map { |id| definitions_by_id[id]&.property_name }
      end

      sig { params(definitions: T::Array[CustomPropertiesCore::IPropertyDefinition]).returns(T::Array[CustomPropertiesCore::IPropertyDefinition]) }
      def explicitly_required_definitions(definitions)
        T.cast(definitions, T::Array[CustomPropertyDefinition]).select(&:require_explicit_values)
      end
    end
  end
end
