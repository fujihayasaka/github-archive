# typed: strict
# frozen_string_literal: true

class CustomPropertiesValuesManager
  include CustomProperties
  include CustomProperties::Errors

  # Public: Initializes a new instance to handle the properties for an org
  #
  # definitions_manager - A definitions object that can be used to manage property definitions
  sig { params(definitions_manager: CustomPropertiesDefinitionsManager).void }
  def initialize(definitions_manager)
    org = definitions_manager.organization
    raise ArgumentError, "Only definitions manager initialized with an org is accepted" if org.nil?

    @org = T.let(org, ::Organization)
    @definitions_manager = definitions_manager
  end

  # Public: Combine manual values with the schema default values
  # to produce a hash of effective values
  # It allows in-memory evaluation without saving new values or the would-be new repo.
  sig { params(manual_values: T::Hash[String, PropertyValue]).returns(T::Hash[String, T.nilable(PropertyValue)]) }
  def get_effective_values(manual_values)
    manual_values = manual_values.reject { |_, value| value.empty? }

    @definitions_manager.get_definitions.to_h do |defn|
      [defn.property_name, manual_values.fetch(defn.property_name, defn.default_value)]
    end
  end

  # Public: Get the manual values for a repo
  #
  # repo - the repository
  #
  # Returns a hash of effective values. Nil values are excluded.
  sig { params(repo: ::Repository).returns(T::Hash[String, PropertyValue]) }
  def get_manual_values_for_repo(repo)
    definitions = @definitions_manager.get_definitions

    grouped_values = CustomPropertyValue.where(target_id: repo.id).group_by(&:definition_id)

    manual_values = grouped_values.each_with_object({}) do |(definition_id, value_row), result|
      definition = definitions.find { |definition| definition.id == definition_id }
      next if definition.nil?

      value = if definition.multi_select_value_type?
        value_row.map(&:value).sort
      else
        T.must(value_row.first).value
      end

      result[definition.property_name] = value
    end
  end

  # Public: Evaluate if a condition is satisfied by a repository's properties
  #
  # repo - the repository to check
  # condition - the condition to check
  # repo_create_custom_properties - the custom properties that would be set on the new repository
  # any_match - whether to require any match instead of all to match
  #
  # Returns true if the repository's properties satisfy the condition, false otherwise
  sig { params(repo: ::Repository, condition: T::Hash[String, T::Array[String]], repo_create_custom_properties: T.nilable(T::Hash[String, PropertyValue]), any_match: T::Boolean).returns(T::Boolean) }
  def evaluate(repo, condition, repo_create_custom_properties = nil, any_match: false)
    values = repo_create_custom_properties.present? ? repo_create_custom_properties : get_manual_values_for_repo(repo)
    effective_values = get_effective_values(values).transform_keys(&:downcase)

    if any_match
      condition.any? do |property_name, expected_values|
        evaluate_part(effective_values, property_name, expected_values)
      end
    else
      condition.all? do |property_name, expected_values|
        evaluate_part(effective_values, property_name, expected_values)
      end
    end
  end

  # Public: Validate values and definitions against the schema for the collection's org
  #
  # properties - A hash of properties to validate
  #
  # Returns an array of errors. Empty array means that properties are valid.
  sig { params(properties: T::Hash[T.any(String, Symbol), PropertyValue]).returns(T::Array[SchemaValidationError]) }
  def validate_properties(properties)
    properties = T.let(properties.stringify_keys, T::Hash[String, PropertyValue])
    CustomPropertiesValidator.validate_properties(@definitions_manager.get_definitions, properties)
  end

  sig do
    params(
      entities: T::Array[::Repository],
      properties: T::Hash[String, PropertyValue],
      actor: T.nilable(AuthzdActor),
    ).void.checked(:always).on_failure(:raise)
  end
  def set_properties_for(entities, properties, actor: nil)
    check_edit_permissions!(actor, entities, properties)
    assert_no_validation_errors!(properties)

    definition_ids_hash = properties.to_h { |name, _| [T.must(@definitions_manager.get_definition(name)).id, name] }

    Repository.transaction do
      entities_values_hash = CustomPropertyValue.where(
        target_id: entities.map(&:id),
        target_type: "Repository",
        definition_id: definition_ids_hash.keys,
      ).group_by(&:target_id)

      entities.each do |entity|
        name_to_rows_group = (entities_values_hash[entity.id] || []).group_by { |row| T.must(definition_ids_hash[row.definition_id]) }
        delete_properties = T.let([], T::Array[CustomPropertyValue])
        create_properties = T.let([], T::Array[[String, String]])

        properties.each_pair do |name, values|
          values = Array(values).compact_blank
          rows = name_to_rows_group.fetch(name, [])
          stored_values = name_to_rows_group.fetch(name, [])
          values_to_create = values - rows.map(&:value)
          rows_to_delete = rows.filter { |row| !values.include?(row.value) }

          delete_properties += rows_to_delete
          create_properties += values_to_create.map { |value| [name, value] }
        end

        # Before update it, we need calculate the old values for the telemetry
        old_properties = properties.keys.index_with do |name|
          definition = T.must(@definitions_manager.get_definition(name))
          values = name_to_rows_group.fetch(name, []).map(&:value).sort

          next nil if values.empty?

          if definition.multi_select_value_type?
            values
          else
            values.first
          end
        end

        delete_properties.each { |row| row.destroy! }
        create_properties.each do |name, value|
          CustomPropertyValue.create!(
            target_id: entity.id,
            target_type: "Repository",
            definition: @definitions_manager.get_definition(name),
            value: value
          )
        end

        if properties.any?
          event_payload = {
            repo: entity,
            org: @org,
            new_values: properties.transform_values { |value| value.blank? ? nil : value },
            old_values: old_properties,
          }

          GitHub.instrument "repo.update_custom_property_values", event_payload
        end
      end
    end

    reindex_repos(entities)
  end

  # When dealing with large orgs, this is the batch size to work on smaller chunks.
  BATCH_SIZE = 1000

  # Public: Delete all values for the given definition in the current org
  # Instrument: repo.delete_custom_property_values once per the whole operation, not per repo
  #
  # definitions - the definitions to delete values for.
  sig { params(definitions: T::Array[CustomProperties::IPropertyDefinition]).void }
  def delete_all_values(definitions)
    definition_ids = definitions.pluck(:id)
    repo_ids = @org.repositories.ids
    repo_ids.each_slice(BATCH_SIZE) do |ids|
      CustomPropertyValue.where(target_id: ids, target_type: "Repository", definition_id: definition_ids).delete_all
    end

    GitHub.instrument "org.delete_custom_property_values_for_definition", {
      org: @org,
      property_name: definitions.pluck(:property_name)
    }

    reindex_org_repos
  end

  # Checks the edit permissions for a given actor, repositories, and properties.
  #
  # actor - the actor for whom the permissions are checked
  # repos - the repositories to check permissions for
  # properties - the properties actor tries to set
  # Raises EditPropertyPermissionError if actor doesn't have permission to edit the properties
  sig do
    params(
      actor: T.nilable(AuthzdActor),
      repos: T::Array[Repository],
      properties: T::Hash[String, T.untyped]
    )
    .void
    .checked(:always).on_failure(:raise)
  end
  def check_edit_permissions!(actor, repos, properties)
    # nilable actors are temporarily allowed but thrown here for backwards compatibility
    raise EditPropertyPermissionError.new("Actor doesn't have permissions to edit properties") unless actor
    repos.each { |repo| assert_owner_is_this_org!(repo) }

    org_permission, *repos_permissions = Promise.all([
      @org.async_can_edit_organization_custom_properties_values?(actor),
      *repos.map { |repo| repo.async_can_edit_custom_property_values_as_repo_actor?(actor) }
    ]).sync

    return if org_permission

    editable_properties = properties.filter_map do |property_name, _|
      definition = @definitions_manager.get_definition(property_name)
      next unless definition

      property_name if definition.values_editable_by == "org_and_repo_actors"
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

  # Checks if the property can be initialized at repo creation time.
  #
  # user - the user that creates the repo
  # property - the property to check.
  # Returns true if the user can set a value to the property when creating a new repo.
  sig { params(user: User, property: String).returns(T::Boolean) }
  def repo_creator_can_initialize_property?(user, property)
    return true if @org.can_edit_organization_custom_properties_values?(user)

    definition = @definitions_manager.get_definition(property)
    return false unless definition

    definition.org_and_repo_actors?
  end

  private

  sig { params(repos: T::Array[Repository]).void }
  def reindex_repos(repos)
    repos.each do |repo|
      Search.add_to_search_index("repository", repo.id)
    end
  end

  sig { void }
  def reindex_org_repos
    BulkReposIndexJob.reindex_org(@org.id)
  end

  sig { params(repo: ::Repository).void }
  def assert_owner_is_this_org!(repo)
    repo_org = T.cast(repo.owner, ::Organization)
    raise ArgumentError, "Invalid entity: repo #{repo} doesn't belong to org #{@org}" unless repo_org == @org
  end

  sig { params(properties: T::Hash[String, T.untyped]).returns(T.nilable(PropertyValidationError)) }
  def assert_no_validation_errors!(properties)
    errors = validate_properties(properties)

    raise PropertyValidationError.new(errors) if errors.any?
  end

  sig { params(effective_values: T::Hash[String, T.nilable(PropertyValue)], property_name: String, expected_values: T.nilable(T.any(String, T::Array[String]))).returns(T::Boolean) }
  def evaluate_part(effective_values, property_name, expected_values)
    current_values = effective_values[property_name.downcase]

    (Array(expected_values).map(&:downcase) & Array(current_values).map(&:downcase)).present?
  end
end
