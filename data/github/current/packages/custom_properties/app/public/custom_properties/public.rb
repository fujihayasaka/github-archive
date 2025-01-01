# typed: strict
# frozen_string_literal: true

module CustomProperties
  module Public
    include Kernel

    extend self

    # Public: Max number of property definitions per org
    DEFINITION_LIMIT = 100

    # Public: Max length of property names and values
    MAX_LENGTH = 75

    # Public: Max length of the description of a property
    DESCRIPTION_MAX_LENGTH = 255

    NAME_VALID_CHARS_REGEX_TEXT = "[a-zA-Z0-9_\\#\\$\\-]+"
    # Public: Regex to validate allowed characters in property names
    NAME_VALID_CHARS_REGEX = /\A#{NAME_VALID_CHARS_REGEX_TEXT}\z/

    # Public: Regex to find forbidden characters in property values. Allows all printable ASCII characters except
    # double quotes.
    #
    # This regex works because `"` is between `!` and `#` in the ASCII table.
    VALUE_INVALID_CHARS_REGEX = /[^ -!#-~]/

    # Public: Gets a definitions manager object used to interact with the properties of an org
    # The object keeps an internal cache of definitions list.
    # It is recommended to memoize it if it is used multiple times in the same request.
    #
    # org - org object. The manager will return definitions for the org and its parent enterprise.
    sig { params(org: Organization).returns(CustomPropertiesDefinitionsManager).checked(:always).on_failure(:raise) }
    def definitions_manager(org)
      CustomPropertiesDefinitionsManager.new(org)
    end

    # Public: Gets a definitions manager object used to interact with the properties of a business
    # The object keeps an internal cache of definitions list.
    # It is recommended to memoize it if it is used multiple times in the same request.
    #
    #   source - business object. When business is passed, it will return definitions for that business.
    sig { params(source: Business).returns(CustomPropertiesBusinessDefinitionsManager).checked(:always).on_failure(:raise) }
    def business_definitions_manager(source)
      CustomPropertiesBusinessDefinitionsManager.new(source)
    end

    # Public: Gets an object used to work with property values in the org
    #
    # definitions_manager - A definitions collection that can be used to manage property definitions
    sig { params(definitions_manager: CustomPropertiesDefinitionsManager).returns(CustomPropertiesValuesManager) }
    def values_manager(definitions_manager)
      CustomPropertiesValuesManager.new(definitions_manager)
    end

    # Returns whether the provided real user has the necessary permissions at to edit properties at each level.
    # `true` will be returned for both levels for users with the org-level FGP, and users with the repo-level FGP
    # will only have `true` returned for the repo level. Does not take into account whether an individual definition
    # allows repo-level editing, that must be manually checked per definition.
    sig do
      params(user: AuthzdActor, repo: Repository)
      .returns(UserEditPermissions)
      .checked(:always).on_failure(:raise)
    end
    def self.user_edit_permissions(user, repo)
      return UserEditPermissions.new(org: false, repo: false) unless repo.owner&.organization?

      # if the above statement doesn't return, then we know it's a non-nil organization
      owner = T.cast(repo.owner, Organization)

      org_level, repo_level = Promise.all([
        owner.async_can_edit_organization_custom_properties_values?(user),
        repo.async_can_edit_custom_property_values_as_repo_actor?(user),
      ]).sync

      UserEditPermissions.new(org: org_level, repo: repo_level)
    end

    # Public: Get the usage of a property
    # Returns a hash with the number of repositories that use the property
    sig { params(definition: IPropertyDefinition).returns(T::Hash[Symbol, Integer]) }
    def self.property_usage(definition)
      repositories_count = CustomPropertyValue.for_active_repos.where(definition_id: definition.id).count

      { repositories_count: }
    end

    # Public: Delete all definition for a given source. Corresponding usages are deleted as well.
    # This method is meant for cleanup purposes only.
    #
    # source - Organization or Business to delete definition for
    sig { params(source: PropertySource).void }
    def self.destroy_all_definitions(source)
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
      CustomPropertyValue.where(target_id: entity.id, target_type: entity.class.name).destroy_all
    end

    # Public: Delete all properties for a given entity and source
    #
    # entity - The entity to delete properties for
    # source - The source to delete properties for
    sig { params(entity: ::Repository, source: PropertySource).void.checked(:always).on_failure(:raise) }
    def destroy_property_values(entity, source)
      definition_ids = CustomPropertyDefinition.defined_by(source).pluck(:id)
      CustomPropertyValue.where(target_id: entity.id, definition_id: definition_ids).destroy_all
    end

    sig { params(source: PropertySource).returns(T::Boolean) }
    def self.enterprise_properties_enabled?(source)
      if source.is_a?(Organization)
        !!source.business&.feature_enabled?(:enterprise_custom_properties)
      else
        source.feature_enabled?(:enterprise_custom_properties)
      end
    end

    # Public: Returns whether the enterprise properties list is enabled for the given source.
    #
    # The flag gates business properties list and search experience.
    # Current flag depends on `enterprise_custom_properties` and will evaluate to false unless the base feature flag is enabled.
    # We support both org and business objects as sources
    # it is required to hide related feature changes for both business and orgs admin pages.
    sig { params(source: PropertySource).returns(T::Boolean) }
    def self.enterprise_properties_list_enabled?(source)
      return false unless enterprise_properties_enabled?(source)

      if source.is_a?(Organization)
        !!source.business&.feature_enabled?(:enterprise_custom_properties_list)
      else
        source.feature_enabled?(:enterprise_custom_properties_list)
      end
    end
  end
end
