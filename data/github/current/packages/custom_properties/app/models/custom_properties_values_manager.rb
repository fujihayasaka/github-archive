# typed: strict
# frozen_string_literal: true

class CustomPropertiesValuesManager
  include CustomProperties
  include CustomProperties::Errors
  include CustomProperties::IValuesManager

  # Public: Initializes a new instance to handle the properties for an org
  #
  # definitions_manager - A definitions object that can be used to manage property definitions
  sig { params(definitions_manager: CustomPropertiesDefinitionsManager).void }
  def initialize(definitions_manager)
    org = if definitions_manager.source.is_a?(::Organization)
      T.cast(definitions_manager.source, ::Organization)
    else
      raise ArgumentError, "Only definitions manager initialized with an org is accepted"
    end

    @org = T.let(org, ::Organization)
    @config = T.let(definitions_manager.config, ICustomPropertiesConfig)
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

  # Public: Validate values and definitions against the schema for the collection's org
  #
  # properties - A hash of properties to validate
  #
  # Returns an array of errors. Empty array means that properties are valid.
  sig { override.params(properties: T::Hash[T.any(String, Symbol), PropertyValue]).returns(T::Array[SchemaValidationError]) }
  def validate_properties(properties)
    properties = T.let(properties.stringify_keys, T::Hash[String, PropertyValue])
    CustomPropertiesValidator.validate_properties(@definitions_manager.get_definitions, properties)
  end

  sig do
    override.params(
      targets: T::Array[T.untyped],
      properties: T::Hash[String, PropertyValue],
      actor: T.nilable(AuthzdActor),
      # Temp flag to move permissions check to the repos domain. FF: `custom_properties_domain_isolation`
      check_permissions: T::Boolean
    ).void.checked(:always).on_failure(:raise)
  end
  def set_properties_for(targets, properties, actor: nil, check_permissions: true)
    target_class_name = T.let(T.unsafe(@config.value_class).target_class_name, String)
    malformed_entity_types = T.let(
      targets.select { |entity| entity.class.name != target_class_name }
      .map { |entity| entity.class.name }
      .uniq, T::Array[String]
    )
    if malformed_entity_types.any?
      raise ArgumentError,
        "Invalid entity: Entities with type #{malformed_entity_types.join(", ")} don't match custom property value target type #{target_class_name}."
    end

    check_edit_permissions!(actor, targets, properties) if check_permissions
    assert_no_validation_errors!(properties)

    definition_ids_hash = properties.to_h { |name, _| [T.must(@definitions_manager.get_definition(name)).id, name] }

    @config.value_class.transaction do
      entities_values_hash = T.unsafe(@config.value_class).for_target_ids(targets.map(&:id)).for_definition_ids(definition_ids_hash.keys).group_by(&:target_id)

      targets.each do |target|
        name_to_rows_group = (entities_values_hash[target.id] || []).group_by { |row| T.must(definition_ids_hash[row.definition_id]) }
        delete_properties = T.let([], T::Array[ValueBase])
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
          @config.value_class.create!(
            target_id: target.id,
            definition: @definitions_manager.get_definition(name),
            value: value
          )
        end

        if properties.any?
          event_payload = {
            repo: target,
            org: @org,
            new_values: properties.transform_values { |value| value.blank? ? nil : value },
            old_values: old_properties,
          }

          GitHub.instrument "repo.update_custom_property_values", event_payload
        end
      end
    end
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

  # Public: Case insensitive search for property values that match a search term for a given definition.
  #
  # property_name  - The name of the property definition to search values for
  # search_term    - The search term to match against property values
  # limit          - Optional maximum number of results to return
  #
  # Returns an array of unique matching property values sorted alphabetically.
  sig { override.params(property_name: String, search_term: String, limit: T.nilable(Integer)).returns(T::Array[String]) }
  def search_property_values(property_name, search_term, limit: nil)
    definition = @definitions_manager.get_definition(property_name)
    raise ArgumentError, "Invalid entity: property with name #{property_name} does not exist in #{@org}'s schema" unless definition

    T.unsafe(@config.value_class).for_definition(definition)
      .with_property_value_like(search_term)
      .order(value: :asc)
      .distinct
      .limit(limit)
      .pluck(:value)
  end

  private

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
end
