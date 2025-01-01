# typed: strict
# frozen_string_literal: true

module CustomProperties
  module Public
    include Kernel
    include CustomPropertiesHelper

    extend self
    extend T::Sig

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
    # source - org or enterprise object. When enterprise is passed, it will return definitions for the enterprise.
    #   When org is passed, it will return definitions for the org and its parent enterprise.
    sig { params(source: PropertySource).returns(CustomPropertiesDefinitionsManager) }
    def definitions_manager(source)
      CustomPropertiesDefinitionsManager.new(source)
    end

    # Public: Gets an object used to work with property values in the org
    #
    # definitions_manager - A definitions collection that can be used to manage property definitions
    sig { params(definitions_manager: CustomPropertiesDefinitionsManager).returns(CustomPropertiesValuesManager) }
    def values_manager(definitions_manager)
      CustomPropertiesValuesManager.new(definitions_manager)
    end

    # This method is a wrapper around `values_for_repos` and `values_hash_to_string_hash`.
    # It calls `values_for_repos` followed by `values_hash_to_string_hash`
    # It provides a shortcut for the cases when we only need to get key value pairs for each repo.
    # It returns a hash of property values for each repo.
    #
    # repos - repos objects
    # value_to_use - One of `:manual` or `:effective`
    # strip_nils - If true (defaults to false), any properties with a nil value will be completely stripped from the
    #   returned hash
    sig do
      params(
        repos: T::Enumerable[Repository],
        value_to_use: Symbol,
        strip_nils: T::Boolean
      ).returns(T::Hash[Repository, T::Hash[String, T.nilable(PropertyValue)]]).checked(:always).on_failure(:raise)
    end
    def self.repo_properties(repos, value_to_use, strip_nils: false)
      values_hash_to_string_hash(values_for_repos(repos), value_to_use, strip_nils:)
    end

    # Returns a hash of properties that apply for each input repo. Repos passed in are returned untouched as the
    # keys of the hash.
    #
    # The array of properties for each repo will be sorted by property name.
    sig do
      params(
        repos: T::Enumerable[Repository]
      ).returns(RepoPropertyValueHash)
      .checked(:always).on_failure(:raise)
    end
    def self.values_for_repos(repos)
      return {} unless repos.any?

      repo_ids = repos.map(&:id)
      owners = repos.map(&:owner)

      if owners.any? { |owner| !owner&.organization? }
        raise ArgumentError, "all repos must belong to an organization"
      end

      org_ids = owners.map { |owner| owner&.id }.uniq
      biz_ids = owners.map { |owner| T.cast(owner, ::Organization).business&.id }.uniq

      # merge all definitions with configured values for each. don't use `includes(:custom_property_values)`
      # because that may query more rows than are needed
      defs_by_org = CustomPropertyDefinition.where(source_id: org_ids, source_type: :org).group_by(&:source_id)
      defs_by_biz = if biz_ids.any?
        CustomPropertyDefinition.where(source_id: biz_ids, source_type: :business).group_by(&:source_id)
      else
        {}
      end
      # At this point we don't know if user needs effective or manual value, but we won't to provide a consistent order for the values
      set_values_by_target = CustomPropertyValue.where(target_id: repo_ids).order(value: :asc).group_by(&:target_id)

      repos.to_h do |repo|
        values_by_repo_def = set_values_by_target.fetch(T.must(repo.id), []).group_by(&:definition_id)

        biz_id = repo.owner&.business&.id
        biz_defs = biz_id ? defs_by_biz.fetch(biz_id, []) : []

        org_defs = defs_by_org.fetch(T.must(repo.owner&.id), [])

        definitions = CustomPropertiesDefinitionsManager.merge_definitions(biz_defs, org_defs)
        prop_array = definitions.flat_map do |defn|
          # check all set values to see if one exists for this definition and repo
          values = values_by_repo_def.fetch(T.must(defn.id), [])
          ValueWithDefinition.new(defn, values)
        end

        [repo, prop_array]
      end
    end

    # Takes the result of `values_for_repos` and returns a hash of property values for each repo.
    #
    # value_hash - The result of `values_for_repos`
    # value_to_use - One of `:manual` or `:effective`
    # strip_nils - If true (defaults to false), any properties with a nil value will be completely stripped from the
    #   returned hash
    sig do
      params(
        value_hash: RepoPropertyValueHash,
        value_to_use: Symbol,
        strip_nils: T::Boolean
      ).returns(T::Hash[Repository, T::Hash[String, T.nilable(PropertyValue)]])
      .checked(:always).on_failure(:raise)
    end
    def self.values_hash_to_string_hash(value_hash, value_to_use, strip_nils: false)
      allowed_values_to_use = [:manual, :effective]
      unless allowed_values_to_use.include?(value_to_use)
        raise ArgumentError, "invalid value specified for value_to_use: #{value_to_use}"
      end

      value_hash.transform_values do |properties|
        values = properties.to_h do |value|
          val = if value_to_use == :manual
            value.manual_value
          else
            value.effective_value
          end

          [value.definition.property_name, val]
        end

        values = values.compact if strip_nils
        values
      end
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
        CustomPropertyUsage.where(definition_id: definitions.pluck(:id)).destroy_all
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

    sig { params(source: PropertySource).returns(T::Boolean) }
    def self.enterprise_properties_enabled?(source)
      if source.is_a?(Organization)
        !!source.business&.feature_enabled?(:enterprise_custom_properties)
      else
        source.feature_enabled?(:enterprise_custom_properties)
      end
    end

    RepoPropertyValueHash = T.type_alias { T::Hash[Repository, T::Array[IPropertyValue]] }
  end
end
