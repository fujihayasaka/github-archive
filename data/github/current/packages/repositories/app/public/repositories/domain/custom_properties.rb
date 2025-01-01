# typed: strict
# frozen_string_literal: true

module Repositories
  class Domain
    class CustomProperties < GH::Domain::Base
      include ::CustomProperties::DomainAccessorBase

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
        ).returns(T::Hash[IRepository, T::Hash[String, T.nilable(::CustomProperties::PropertyValue)]]).checked(:always).on_failure(:raise)
      end
      def repo_properties(repos, value_to_use, strip_nils: false)
        check_repos_owner!(repos)
        values_for_targets(repos, value_to_use:, strip_nils:)
      end

      # Public: Returns whether the given user can see property definitions for the given source.
      #
      # user - The user to check permissions for
      # source - The source to check permissions for, either an Organization or a Business
      sig do
        params(
          user: ::CustomProperties::AuthzdActor,
          source: ::CustomProperties::PropertySource
        ).returns(T::Boolean)
        .checked(:always).on_failure(:raise)
      end
      def can_see_property_definitions?(user, source)
        if user.can_have_granular_permissions?
          resource = source.is_a?(Organization) ? source.resources.organization_custom_properties : source.resources.enterprise_custom_properties
          resource.readable_by?(user)
        elsif source.is_a?(Organization)
          source.member?(user)
        else
          source.readable_by?(user)
        end
      end

      # Returns whether the provided real user has the necessary permissions at to edit properties at each level.
      # `true` will be returned for both levels for users with the org-level FGP, and users with the repo-level FGP
      # will only have `true` returned for the repo level. Does not take into account whether an individual definition
      # allows repo-level editing, that must be manually checked per definition.
      sig do
        params(user: ::CustomProperties::AuthzdActor, repo: Repository)
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

      # Public: Get the usage of a property
      # Returns a hash with the number of repositories that use the property
      sig { params(definition: ::CustomProperties::IPropertyDefinition).returns(T::Hash[Symbol, Integer]) }
      def property_usage(definition)
        repositories_count = CustomPropertyValue.for_definition(definition).with_target_scope.count

        { repositories_count: }
      end

      # Public: Delete all definition for a given source. Corresponding usages are deleted as well.
      # This method is meant for cleanup purposes only.
      #
      # source - Organization or Business to delete definition for
      sig { params(source: ::CustomProperties::PropertySource).void }
      def destroy_all_definitions(source)
        Repository.transaction do
          definitions = CustomPropertyDefinition.defined_by(source)
          definitions.destroy_all
        end
      end

      # Public: Delete all properties for a given entity
      #
      # entity - The entity to delete properties for
      sig { params(entity: ::Repository).void.checked(:always).on_failure(:raise) }
      def destroy_all_properties(entity)
        CustomPropertyValue.where(target_id: entity.id).destroy_all
      end

      # Public: Delete all properties for a given entity and source
      #
      # entity - The entity to delete properties for
      # source - The source to delete properties for
      sig { params(entity: ::Repository, source: ::CustomProperties::PropertySource).void.checked(:always).on_failure(:raise) }
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
      def save_definition(source, property_name:, value_type: "string", required: false, default_value: nil, description: nil, allowed_values: nil, values_editable_by: "org_actors", regex: nil) # rubocop:disable Metrics/MethodLength
        existing_definition = get_definition(source, property_name)
        should_reindex = if existing_definition
          existing_definition.required != required || existing_definition.default_value != default_value
        else
          required
        end

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

        reindex_source_repos(source) if should_reindex
        result
      end

      # Public: Delete definition
      #
      # Returns the deleted definition or nil if it did not exist
      sig { override.params(source: ::CustomProperties::PropertySource, property_name: String).returns(T.nilable(::CustomProperties::IPropertyDefinition)) }
      def delete_definition(source, property_name)
        result = super(source, property_name)

        reindex_source_repos(source)
        result
      end

      # Public: Promote a property definition from an organization to the enterprise level.
      #
      # Promotion requires using business level definitions manager.
      # Property can be promoted only if there are no other properties with the same name in the enterprise orgs.
      #
      # definition - Org level property definition to promote
      # Returns promoted property definition
      sig { override.params(business: ::Business, definition: ::CustomProperties::IPropertyDefinition).returns(::CustomProperties::IPropertyDefinition) }
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
          source: ::CustomProperties::PropertySource,
          targets: T::Array[IRepository],
          properties: T::Hash[String, ::CustomProperties::PropertyValue],
          actor: T.nilable(::CustomProperties::AuthzdActor),
          # Added for signature compatibility. Must be dropped with FF `custom_properties_domain_isolation`
          check_permissions: T::Boolean,
        ).void
      end
      def set_properties_for(source, targets, properties, actor: nil, check_permissions: true)
        if GitHub.flipper[:custom_properties_domain_isolation].enabled?
          raise EditPropertyPermissionError.new("Actors can only edit properties for organization source") unless source.is_a?(Organization)

          check_edit_permissions!(source, actor, targets, properties)
          super(source, targets, properties, actor:,  check_permissions: false)
        else
          super(source, targets, properties, actor:, check_permissions: true)
        end
        reindex_repos(targets)
      end

      # Public: Evaluate if a condition is satisfied by a given set of properties
      #
      # effective_properties - the properties to check
      # condition - the condition to check
      # any_match - whether to require any match instead of all to match
      #
      # Returns true if the given properties satisfy the condition, false otherwise
      sig do
        params(
          effective_properties: T::Hash[String, T.nilable(::CustomProperties::PropertyValue)],
          # Remove T::Hash[String, T::Array[String]] from condition when the feature flag ruleset_allow_dup_multi_select_props is removed
          condition: T.any(T::Array[{ name: String, values: T.nilable(T::Array[String]) }], T::Hash[String, T::Array[String]]),
          any_match: T::Boolean
        ).returns(T::Boolean)
      end
      def evaluate_effective_custom_properties(effective_properties, condition, any_match: false) # rubocop:todo Metrics/MethodLength
        effective_properties = effective_properties.transform_keys(&:downcase)

        if condition.is_a? Array
          conditions = condition.map { |cond| [cond[:name], cond[:values]] }
          if any_match
            conditions.any? { |property_name, expected_values| evaluate_part(effective_properties, property_name, expected_values) }
          else
            conditions.all? { |property_name, expected_values| evaluate_part(effective_properties, property_name, expected_values) }
          end
        else
          # Remove it when the feature flag ruleset_allow_dup_multi_select_props is removed
          if any_match
            condition.any? do |property_name, expected_values|
              evaluate_part(effective_properties, property_name, expected_values)
            end
          else
            condition.all? do |property_name, expected_values|
              evaluate_part(effective_properties, property_name, expected_values)
            end
          end
        end
      end

      # Public: Combine manual values with the schema default values
      # to produce a hash of effective values
      # It allows in-memory evaluation without saving new values or the would-be new repo.
      sig { params(source: ::CustomProperties::PropertySource, manual_values: T::Hash[String, ::CustomProperties::PropertyValue]).returns(T::Hash[String, T.nilable(::CustomProperties::PropertyValue)]) }
      def get_effective_values(source, manual_values)
        manual_values = manual_values.reject { |_, value| value.empty? }

        get_definitions(source).to_h do |defn|
          [defn.property_name, manual_values.fetch(defn.property_name, defn.default_value)]
        end
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
        RemoveBusinessCustomPropertyValuesFromOrgJob.perform_later(business: business, org: org)
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
        RemoveRepoCustomPropertyDefinitionOrgConflictsJob.perform_later(business: business, org: org)
      end

      # Checks if the property can be initialized at repo creation time.
      #
      # org - the organization that owns the repo
      # user - the user that creates the repo
      # property - the property to check.
      # Returns true if the user can set a value to the property when creating a new repo.
      sig { params(org: ::Organization, user: User, property: String).returns(T::Boolean) }
      def repo_creator_can_initialize_property?(org, user, property)
        return true if org.can_edit_organization_custom_properties_values?(user)

        definition = get_definition(org, property)
        return false unless definition

        editable_by_repo_actors?(definition)
      end

      # Public: Check if the definition is editable by org and repo actors
      #
      # definition - The property definition to check
      #
      # Returns true if the definition is editable by repo actors, false otherwise
      sig { params(definition: ::CustomProperties::IPropertyDefinition).returns(T::Boolean) }
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
      sig do
        params(
          source: Organization,
          actor: T.nilable(::CustomProperties::AuthzdActor),
          repos: T::Array[IRepository],
          properties: T::Hash[String, T.untyped]
        )
        .void
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

        return if org_permission

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
      end

      private

      sig { override.returns(::CustomProperties::ICustomPropertiesConfig) }
      def config
        @config ||= T.let(RepoPropertiesConfig.new, T.nilable(::CustomProperties::ICustomPropertiesConfig))
      end

      sig { params(effective_values: T::Hash[String, T.nilable(::CustomProperties::PropertyValue)], property_name: String, expected_values: T.nilable(T.any(String, T::Array[String]))).returns(T::Boolean) }
      def evaluate_part(effective_values, property_name, expected_values)
        current_values = effective_values[property_name.downcase]

        (Array(expected_values).map(&:downcase) & Array(current_values).map(&:downcase)).present?
      end

      sig { params(source: ::CustomProperties::PropertySource).void }
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
    end
  end
end
