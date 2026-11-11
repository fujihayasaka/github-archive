# typed: strict
# frozen_string_literal: true

class ActionsPolicyHelper
  include Instrumentation::Model

  REPO_CACHE_SIZE_MINIMUM_GB = T.let(10.freeze, Integer)
  REPO_CACHE_SIZE_DEFAULT_GB = T.let(10.freeze, Integer)
  GLOBAL_MAX_CACHE_SIZE_GB = T.let(10000.freeze, Integer)

  CACHE_RETENTION_DAYS_MINIMUM = T.let(1.freeze, Integer)
  CACHE_RETENTION_DAYS_DEFAULT = T.let(7.freeze, Integer)
  GLOBAL_MAX_CACHE_RETENTION_DAYS_PUBLIC = T.let(90.freeze, Integer)
  GLOBAL_MAX_CACHE_RETENTION_DAYS_PRIVATE = T.let(365.freeze, Integer)

  ACTIONS_CACHE_PRODUCT = T.let("actions".freeze, String)
  ACTIONS_CACHE_SKU = T.let("actions_cache_storage".freeze, String)
  CAN_PROCEED_WITH_USAGE_TIMEOUT_SECONDS = T.let(2.freeze, Integer)

  ACTIONS_CACHE_NONBILLABLE_MESSAGE = T.let("Please ensure your account has a valid payment method on file to access this service.".freeze, String)

  sig do
    params(entity: T.any(Repository, Organization, Business)).
    returns(T.untyped).
    checked(:always).
    on_failure(:raise)
  end
  def self.entity_can_use_cache_policies?(entity)
    customer_id = Billing::EntityResolver.customer_id(entity)
    return false if customer_id.nil?

    entity_detail = BillingPlatform::Base::EntityDetail.new(
      customerId: customer_id.to_s
    )

    usage_key = BillingPlatform::Api::V1::UsageKey.new(
      product: ACTIONS_CACHE_PRODUCT,
      sku: ACTIONS_CACHE_SKU,
      entityDetail: entity_detail,
      usageAt: Time.now.to_i
    )

    client = ::Billing::Platform::Api::Client.new(timeout: CAN_PROCEED_WITH_USAGE_TIMEOUT_SECONDS)
    response = client.can_proceed_with_usage(usage_key: usage_key)

    # Fail open
    return true if response.is_a?(Billing::Platform::Api::Error)

    # Allow either users who can proceed, or those who are failing due to exceeded budgets.
    response[:canProceed] || (response[:status] == :BudgetLimitReached) || (response[:status] == :TrustTierUsageLimitReached)
  end

  # Returns an array of cache storage policies for the entity and its parent entities.
  # Each policy contains the entity and its storage limit in GB (or nil if no policy is set for that entity).
  # Returns nil if the Twirp call fails.
  sig do
    params(entity: T.any(Repository, Organization, Business)).
    returns(T.nilable(T::Array[{ entity: T.any(Repository, Organization, Business), storage_limit: T.nilable(Integer) }])).
    checked(:always).
    on_failure(:raise)
  end
  def self.get_cache_limits(entity)
    relevant_entities = get_relevant_entities(entity: entity)
    get_cache_limits_from_entities(relevant_entities)
  end

  # Returns an array of cache storage policies, given the list of entities concerned.
  # Each policy contains the entity and its storage limit in GB (or nil if no policy is set for that entity).
  # Returns nil if the Twirp call fails.
  sig do
    params(relevant_entities: T::Array[T.any(Repository, Organization, Business)]).
    returns(T.nilable(T::Array[{ entity: T.any(Repository, Organization, Business), storage_limit: T.nilable(Integer) }])).
    checked(:always).
    on_failure(:raise)
  end
  def self.get_cache_limits_from_entities(relevant_entities)
    primitive_entities = entities_to_primitives(relevant_entities)
    result = ActionsResults::Twirp.policies_client.get_cache_storage_policy(policy_entities: primitive_entities)

    return nil if result.nil?

    # Convert primitive results back to domain objects
    result.map do |primitive_entity|
      domain_entity = find_entity_by_type_and_id(relevant_entities, primitive_entity[:entity_type], primitive_entity[:entity_id])
      {
        entity: domain_entity,
        storage_limit: primitive_entity[:storage_limit]
      }
    end
  end

  # Returns the cache size limit to be enforced for the given entity. Will return default values if no policies set.
  sig { params(entity: T.any(Repository, Organization, Business)).returns(Integer) }
  def self.get_applied_cache_storage_limit(entity)
    limits = get_cache_limits(entity)

    return REPO_CACHE_SIZE_DEFAULT_GB unless limits&.any?

    # For this functionality to be truly opt-in, enterprises must set limits before enclosed organisations can set their limits
    # Only then can repositories at the bottom of this hierarchy set a limit.
    is_any_entity_unset = limits.any? { |e| e[:storage_limit].nil? }

    return REPO_CACHE_SIZE_DEFAULT_GB if is_any_entity_unset

    # Policy is set at all levels so we can just take the lowest.
    T.must(limits.min_by { |e| e[:storage_limit] })[:storage_limit]
  end

  # Returns the cache retention period in days to be enforced for the given entity. Will return default values if no policies set.
  sig { params(entity: T.any(Repository, Organization, Business)).returns(Integer) }
  def self.get_applied_cache_retention(entity)
    limits = get_cache_retention(entity)

    return CACHE_RETENTION_DAYS_DEFAULT unless limits&.any?

    # For this functionality to be truly opt-in, enterprises must set limits before enclosed organisations can set their limits
    # Only then can repositories at the bottom of this hierarchy set a limit.
    is_any_entity_unset = limits.any? { |e| e[:retain_for].nil? }

    return CACHE_RETENTION_DAYS_DEFAULT if is_any_entity_unset

    # Policy is set at all levels so we can just take the lowest.
    T.must(limits.min_by { |e| e[:retain_for] })[:retain_for]
  end

  # Returns an array of cache retention policies for the entity and its parent entities.
  # Each policy contains the entity and its retention period in days (or nil if no policy is set for that entity).
  # Returns nil if the Twirp call fails.
  sig do
    params(entity: T.any(Repository, Organization, Business)).
    returns(T.nilable(T::Array[{ entity: T.any(Repository, Organization, Business), retain_for: T.nilable(Integer) }])).
    checked(:always).
    on_failure(:raise)
  end
  def self.get_cache_retention(entity)
    relevant_entities = get_relevant_entities(entity: entity)
    get_cache_retention_from_entities(relevant_entities)
  end

  # Returns an array of cache retention policies, given the list of entities concerned.
  # Each policy contains the entity and its retention period in days (or nil if no policy is set for that entity).
  # Returns nil if the Twirp call fails.
  sig do
    params(relevant_entities: T::Array[T.any(Repository, Organization, Business)]).
    returns(T.nilable(T::Array[{ entity: T.any(Repository, Organization, Business), retain_for: T.nilable(Integer) }])).
    checked(:always).
    on_failure(:raise)
  end
  def self.get_cache_retention_from_entities(relevant_entities)
    primitive_entities = entities_to_primitives(relevant_entities)
    result = ActionsResults::Twirp.policies_client.get_cache_retention_policy(policy_entities: primitive_entities)

    return nil if result.nil?

    # Convert primitive results back to domain objects
    result.map do |primitive_entity|
      domain_entity = find_entity_by_type_and_id(relevant_entities, primitive_entity[:entity_type], primitive_entity[:entity_id])
      {
        entity: domain_entity,
        retain_for: primitive_entity[:retain_for]
      }
    end
  end

  # Creates or updates a cache storage policy for the given entity with the specified storage limit in GB.
  # Returns true if successful, nil if the Twirp call fails.
  sig do
    params(entity: T.any(Repository, Organization, Business), storage_limit: Integer, current_user: User).
    returns(T.nilable(T::Boolean)).
    checked(:always).
    on_failure(:raise)
  end
  def self.upsert_cache_storage_policy(entity, storage_limit, current_user:)
    # Validate storage limit bounds
    min_limit = ActionsPolicyHelper::REPO_CACHE_SIZE_MINIMUM_GB
    max_limit = find_max_limit_from_enclosing_objects(entity)

    unless storage_limit.between?(min_limit, max_limit)
      raise ActionsCacheUsagePolicy::InvalidLimitError.new("Repository cache size limit must be between #{min_limit} and #{max_limit}.")
    end

    result = ActionsResults::Twirp.policies_client.upsert_cache_storage_policy(
      entity_type: entity_type_code(entity),
      entity_id: entity.id,
      storage_limit: storage_limit,
      actor_id: current_user.id.to_s
    )

    if result
      instrument_cache_storage_policy_change(entity, storage_limit, current_user)
    end

    result
  end

  # Creates or updates a cache retention policy for the given entity with the specified retention period in days.
  # Returns true if successful, nil if the Twirp call fails.
  sig do
    params(entity: T.any(Repository, Organization, Business), retain_for: Integer, current_user: User).
    returns(T.nilable(T::Boolean)).
    checked(:always).
    on_failure(:raise)
  end
  def self.upsert_cache_retention_policy(entity, retain_for, current_user:)
    min_limit = CACHE_RETENTION_DAYS_MINIMUM
    max_limit = find_max_retention_from_enclosing_objects(entity)
    unless retain_for.between?(min_limit, max_limit)
      raise ActionsCacheUsagePolicy::InvalidLimitError.new("Repository retention period must be between #{min_limit} and #{max_limit}.")
    end

    result = ActionsResults::Twirp.policies_client.upsert_cache_retention_policy(
      entity_type: entity_type_code(entity),
      entity_id: entity.id,
      retain_for: retain_for,
      actor_id: current_user.id.to_s
    )

    if result
      instrument_cache_retention_policy_change(entity, retain_for, current_user)
    end

    result
  end

  # Returns an array of entities relevant for policy evaluation, starting with the given entity
  # and including all parent entities in the hierarchy (repository -> organization -> business).
  # The include_self parameter controls whether the entity itself is included in the result.
  #
  # Does NOT include non-organization Users!
  sig { params(entity: T.any(Repository, Business, Organization), include_self: T::Boolean).returns(T::Array[T.any(Repository, Business, Organization)]) }
  def self.get_relevant_entities(entity:, include_self: true)
    entities = []
    entities << entity if include_self

    if entity.is_a?(Repository)
      if entity.owner&.is_a?(Organization)
        entities << entity.owner
        if entity.owner&.business
          entities << entity.owner&.business
        end
      end
    elsif entity.is_a?(Organization)
      if entity.business
        entities << entity.business
      end
    end
    entities
  end

  # Returns the lowest limit from enclosing objects, or GLOBAL_MAX_CACHE_SIZE_GB if no enclosing objects impose a limit.
  # Returns the lowest storage limit from enclosing entities in the ownership hierarchy, or global max if no enclosing entities exist.
  # If any enclosing entity has no limit set, returns the default to enforce opt-in hierarchy.
  sig { params(entity: T.any(Repository, Organization, Business)).returns(Integer) }
  def self.find_max_limit_from_enclosing_objects(entity)
    # Get only the enclosing entities (exclude self)
    enclosing_entities = get_relevant_entities(entity: entity, include_self: false)
    return GLOBAL_MAX_CACHE_SIZE_GB if enclosing_entities.empty?

    # Get limits for enclosing entities only - avoid redundant API call by fetching only what we need
    result = ActionsResults::Twirp.policies_client.get_cache_storage_policy(policy_entities: entities_to_primitives(enclosing_entities))
    return REPO_CACHE_SIZE_DEFAULT_GB if result.nil?

    # Check if any enclosing entity has no limit set - enforce opt-in hierarchy
    # Use composite key "type:id" to avoid collisions (e.g., repo ID 123 != business ID 123)
    enclosing_limits_hash = result.to_h { |primitive_entity| ["#{primitive_entity[:entity_type]}:#{primitive_entity[:entity_id]}", primitive_entity[:storage_limit]] }
    is_any_enclosing_entity_unset = enclosing_entities.any? { |e| enclosing_limits_hash["#{entity_type_code(e)}:#{e.id}"].nil? }

    return REPO_CACHE_SIZE_DEFAULT_GB if is_any_enclosing_entity_unset

    # All enclosing entities have limits set, return the minimum
    enclosing_limits_hash.values.compact.min
  end

  # Returns the lowest retention limit from enclosing entities in the ownership hierarchy, or relevant max retention period if no enclosing entities exist.
  # If any enclosing entity has no limit set, returns the default to enforce opt-in hierarchy.
  # Returned period varies based on whether repositories are public or not (internal treated as private).
  sig { params(entity: T.any(Repository, Organization, Business)).returns(Integer) }
  def self.find_max_retention_from_enclosing_objects(entity)
    # Get only the enclosing entities (exclude self)
    enclosing_entities = get_relevant_entities(entity: entity, include_self: false)

    # If no enclosing entities exist, return entity-specific global max
    if enclosing_entities.empty?
      return is_public_repo?(entity) ? GLOBAL_MAX_CACHE_RETENTION_DAYS_PUBLIC : GLOBAL_MAX_CACHE_RETENTION_DAYS_PRIVATE
    end

    # Get limits for enclosing entities only - avoid redundant API call by fetching only what we need
    result = ActionsResults::Twirp.policies_client.get_cache_retention_policy(policy_entities: entities_to_primitives(enclosing_entities))
    return CACHE_RETENTION_DAYS_DEFAULT if result.nil?

    # Check if any enclosing entity has no limit set - enforce opt-in hierarchy
    # Use composite key "type:id" to avoid collisions (e.g., repo ID 123 != business ID 123)
    enclosing_limits_hash = result.to_h { |primitive_entity| ["#{primitive_entity[:entity_type]}:#{primitive_entity[:entity_id]}", primitive_entity[:retain_for]] }
    is_any_enclosing_entity_unset = enclosing_entities.any? { |e| enclosing_limits_hash["#{entity_type_code(e)}:#{e.id}"].nil? }

    return CACHE_RETENTION_DAYS_DEFAULT if is_any_enclosing_entity_unset

    # All enclosing entities have limits set, return the minimum
    enclosing_limits_hash.values.compact.min
  end

  # Returns a numeric code representing the entity type for use with external APIs.
  # Repository: 1, Organization: 2, Business: 3
  sig { params(entity: T.any(Repository, Organization, Business)).returns(Integer) }
  def self.entity_type_code(entity)
    case entity
    when Repository
      1
    when Organization
      2
    when Business
      3
    end
  end

  # Converts an array of domain entities to an array of primitive hashes
  sig { params(entities: T::Array[T.any(Repository, Organization, Business)]).returns(T::Array[{ entity_type: Integer, entity_id: Integer }]) }
  def self.entities_to_primitives(entities)
    entities.map do |entity|
      {
        entity_type: entity_type_code(entity),
        entity_id: entity.id
      }
    end
  end

  # Finds a domain entity from an array by matching its type and ID
  sig { params(entities: T::Array[T.any(Repository, Organization, Business)], entity_type: Integer, entity_id: Integer).returns(T.any(Repository, Organization, Business)) }
  def self.find_entity_by_type_and_id(entities, entity_type, entity_id)
    entities.find do |entity|
      entity_type_code(entity) == entity_type && entity.id == entity_id
    end || T.must(entities.first) # Fallback, should not happen in practice
  end

  sig { params(entity: T.any(Repository, Organization, Business)).returns(T::Boolean) }
  def self.is_public_repo?(entity)
    entity.is_a?(Repository) && entity.public?
  end

  # Instrument audit log events for cache storage policy changes
  sig do
    params(entity: T.any(Repository, Organization, Business), storage_limit: Integer, current_user: User).
    void.
    checked(:always).
    on_failure(:raise)
  end
  def self.instrument_cache_storage_policy_change(entity, storage_limit, current_user)
    event_key = "set_actions_cache_storage_policy"
    payload = {
      actor: current_user,
      storage_limit: storage_limit
    }
    payload.merge!(build_entity_payload(entity))

    entity.instrument(event_key, payload)
  end

  # Instrument audit log events for cache retention policy changes
  sig do
    params(entity: T.any(Repository, Organization, Business), retain_for: Integer, current_user: User).
    void.
    checked(:always).
    on_failure(:raise)
  end
  def self.instrument_cache_retention_policy_change(entity, retain_for, current_user)
    event_key = "set_actions_cache_retention_policy"
    payload = {
      actor: current_user,
      retain_for: retain_for
    }
    payload.merge!(build_entity_payload(entity))

    entity.instrument(event_key, payload)
  end

  # Instrument audit log events for cache storage policy deletion
  sig do
    params(entity: T.any(Repository, Organization, Business), current_user: User).
    void.
    checked(:always).
    on_failure(:raise)
  end
  def self.instrument_cache_storage_policy_deletion(entity, current_user)
    event_key = "delete_actions_cache_storage_policy"
    payload = {
      actor: current_user
    }
    payload.merge!(build_entity_payload(entity))

    entity.instrument(event_key, payload)
  end

  # Instrument audit log events for cache retention policy deletion
  sig do
    params(entity: T.any(Repository, Organization, Business), current_user: User).
    void.
    checked(:always).
    on_failure(:raise)
  end
  def self.instrument_cache_retention_policy_deletion(entity, current_user)
    event_key = "delete_actions_cache_retention_policy"
    payload = {
      actor: current_user
    }
    payload.merge!(build_entity_payload(entity))

    entity.instrument(event_key, payload)
  end

  # Build entity-specific payload for audit log events
  sig do
    params(entity: T.any(Repository, Organization, Business)).
    returns(T::Hash[Symbol, T.any(Repository, Organization, Business)])
  end
  def self.build_entity_payload(entity)
    payload = case entity
    when Repository
      { repo: entity }
    when Organization
      { org: entity }
    when Business
      { business: entity }
    end

    parent_entities = get_relevant_entities(entity: entity, include_self: false)

    parent_entities.each do |parent|
      case parent
      when Organization
        payload[:org] = parent
      when Business
        payload[:business] = parent
      end
    end

    payload
  end

  private_class_method :find_entity_by_type_and_id, :is_public_repo?, :instrument_cache_storage_policy_change,
                       :instrument_cache_retention_policy_change, :instrument_cache_storage_policy_deletion,
                       :instrument_cache_retention_policy_deletion, :build_entity_payload
end
