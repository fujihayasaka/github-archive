# typed: true
# frozen_string_literal: true

class Copilot::Chat::CopilotSpacesController < Copilot::Chat::AbstractChatController
  include CopilotSpaces::Pagination

  allow_verified_fetch only: [:index, :search]
  before_action :require_copilot_spaces_feature_enabled

  # Maximum number of search results to return from the API
  SEARCH_RESULTS_LIMIT = 10

  # Batch size when filtering for editable spaces to avoid checking all spaces
  EDITABLE_BATCH_SIZE = 50

  rescue_from ActiveRecord::RecordNotFound, with: :render_404

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    only: [:index, :show, :search, :count]

  def index
    # Check if pagination parameters are provided
    if params[:after].present? || params[:before].present? || params[:per_page].present?
      render_paginated_index
    else
      render_unpaginated_index
    end
  end

  def count # rubocop:disable GitHub/UseRestfulActions
    render json: {
      shared_with_me_spaces: shared_with_me_copilot_spaces.count,
      org_owned_spaces: org_owned_copilot_spaces.count,
      user_owned_spaces: user_owned_copilot_spaces.count,
      starred_spaces: starred_copilot_spaces.count,
    }
  end

  def search # rubocop:disable GitHub/UseRestfulActions
    spaces_scope = build_spaces_scope_for_search(params)
    filter_to_editable = params[:editable_only] == "true"

    query = params[:q]&.strip
    if query.blank?
      spaces = CopilotSpace.filter_by_cap_and_sort(spaces_scope, cap_filter, current_user)

      spaces = if filter_to_editable
        collect_editable_spaces(spaces, SEARCH_RESULTS_LIMIT)
      else
        spaces.first(SEARCH_RESULTS_LIMIT)
      end

      return render json: to_camel_case_json(serialize_spaces(spaces))
    end

    return render json: { error: "Query too long" }, status: :bad_request if query.length > 100

    spaces_scope = spaces_scope.where("name LIKE ?", "%#{query.downcase}%")
    spaces = CopilotSpace.filter_by_cap_and_sort(spaces_scope, cap_filter, current_user)
    spaces = if filter_to_editable
      collect_editable_spaces(spaces, SEARCH_RESULTS_LIMIT)
    else
      spaces.first(SEARCH_RESULTS_LIMIT)
    end

    render json: to_camel_case_json(serialize_spaces(spaces))
  end

  def show
    started_at = Time.now
    copilot_space = if params[:owner].present? && params[:number].present?
      CopilotSpace.for_owner_login_and_number_with_user_roles!(params[:owner], params[:number])
    else
      # We need user_roles to determine if the space is accessible because it has collaborators or is a public space
      CopilotSpace.includes(:user_roles).find_by!(id: params[:id])
    end

    return render_404 unless copilot_space.readable_by?(current_user)

    payload = {}
    protected_organizations = copilot_space.protected_organizations(cap_filter: cap_filter)
    if copilot_space.owner.organization? && cap_filter.unauthorized_resources([copilot_space.owner]).any?
      owner_display_login = copilot_space.owner.display_login
      protected_organizations |= [owner_display_login]
    end

    if protected_organizations.any?
      payload = {
        protectedOrganizations: protected_organizations,
      }
    else
      assign_user_and_cap(copilot_space)
      payload_as_json_start = Time.now
      data = CopilotSpaces::PageData::CopilotSpace::Payload.call(copilot_space)
      payload = data.as_json
      payload_as_json_elapsed_time_seconds = Time.now - payload_as_json_start

      CopilotSpaces::HydroEventsHelper.instrument_generic_event("show", current_user, copilot_space, data: {
        controller: self.class.name,
        elapsed_time: Time.now - started_at,
        payload_as_json_elapsed_time_seconds: payload_as_json_elapsed_time_seconds,
        size_percentage: data.sizePercentage,
      })
    end

    render json: payload
  end

  private

  memoize def copilot_spaces
    CopilotSpace.includes(:creator).visible_to(current_user, cap_filter)
  end

  memoize def starred_copilot_spaces
    CopilotSpace.starred_by_with_cap_filter(current_user, cap_filter)
  end

  memoize def user_owned_copilot_spaces
    CopilotSpace.owned_by_user(current_user, cap_filter)
  end

  memoize def org_owned_copilot_spaces
    CopilotSpace.org_owned_spaces(current_user, cap_filter)
  end

  memoize def shared_with_me_copilot_spaces
    CopilotSpace.shared_with_user_spaces(current_user, cap_filter)
  end

  # Returns copilot spaces filtered by the type parameter
  # @return [Array<CopilotSpace>] filtered list of copilot spaces
  def filtered_copilot_spaces_by_type
    spaces = case params[:type]
    when "starred"
      starred_copilot_spaces
    when "user_owned"
      user_owned_copilot_spaces
    when "org_owned"
      org_owned_copilot_spaces
    when "shared_with_user"
      shared_with_me_copilot_spaces
    else
      copilot_spaces
    end

    spaces = apply_individual_access_filter(spaces)

    apply_individual_sharing_filter(spaces)
  end

  # Compute shareable status per unique owner to avoid N policy checks
  # @param spaces [Enumerable<CopilotSpace>] the spaces to check (Array or ActiveRecord::Relation)
  # @return [Hash<Integer, Boolean>] map of owner_id => shareable status
  sig { params(spaces: T.untyped).returns(T::Hash[Integer, T::Boolean]) }
  def compute_shareable_by_owner(spaces)
    # Early return if feature flag is disabled - all spaces are shareable
    unless FeatureFlag.vexi.enabled?(:copilot_spaces_individual_policies_ga, current_user, default: false)
      result = T.let({}, T::Hash[Integer, T::Boolean])
      spaces.each { |space| result[space.owner_id] = true }
      return result
    end

    # Group spaces by owner_id
    spaces_by_owner = spaces.group_by(&:owner_id)

    shareable_map = T.let({}, T::Hash[Integer, T::Boolean])
    spaces_by_owner.each do |_owner_id, owner_spaces|
      owner = owner_spaces.first&.owner
      # Organization-owned spaces are always shareable
      if owner&.organization?
        owner_spaces.each { |space| shareable_map[space.owner_id] = true }
      else
        # For user-owned spaces, check the policy once per unique user
        is_shareable = owner ? Copilot::Policies::SpacesIndividualSharing.effective_value(Copilot::User.new(owner)) == "enabled" : false
        owner_spaces.each { |space| shareable_map[space.owner_id] = is_shareable }
      end
    end

    shareable_map
  end

  # Renders the unpaginated index response (original behavior)
  def render_unpaginated_index
    spaces = filtered_copilot_spaces_by_type

    # Aggregate shareable checks per unique user owner to avoid N policy checks
    shareable_by_owner = compute_shareable_by_owner(spaces)

    json = spaces.map.with_index do |copilot, _index|
      assign_user_and_cap(copilot)
      CopilotSpaces::PageData::CopilotSpace::IndexPayload.call(
        copilot,
        editable: true,
        adminable: true,
        shareable: shareable_by_owner[copilot.owner_id]
      ).as_json
    end

    render json: to_camel_case_json(json)
  end

  # Renders the paginated index response using find_spaces
  def render_paginated_index
    per_page = parse_per_page(params)
    current_cursor = parse_pagination_cursor(params, per_page)

    # Get the base scope and convert to a queryable relation if needed
    scope = filtered_copilot_spaces_by_type
    scope = if scope.is_a?(ActiveRecord::Relation)
      scope.includes(:owner, :resources)
    else
      # This is just in case filtered_copilot_spaces_by_type returns copilot_spaces which is an array
      # This should never happen as long as the type parameter is used, but we handle both cases to be safe
      CopilotSpace.where(id: Array(scope).map(&:id)).includes(:owner, :resources)
    end

    # Use find_spaces for cross-owner pagination (uses id-based cursors)
    spaces_plus_one = find_spaces(scope, current_cursor)
    pagination_result = calculate_pagination_response(spaces_plus_one, current_cursor, per_page, sort_field: :id)

    # Set pagination Link headers
    if request.present? && response.present?
      link_header = generate_pagination_link_header(pagination_result[:cursors], per_page, request.url.split("?").first)
      response.headers["Link"] = link_header if link_header
    end

    spaces = pagination_result[:spaces]

    # Aggregate shareable checks per unique user owner to avoid N policy checks
    shareable_by_owner = compute_shareable_by_owner(spaces)

    # Generate the same formatted response using IndexPayload
    json = spaces.map.with_index do |copilot, _index|
      assign_user_and_cap(copilot)
      CopilotSpaces::PageData::CopilotSpace::IndexPayload.call(
        copilot,
        editable: true,
        adminable: true,
        shareable: shareable_by_owner[copilot.owner_id]
      ).as_json
    end
    render json: to_camel_case_json(json)
  end

  sig { params(array: T::Array[Hash]).returns(T::Array[Hash]) }
  def to_camel_case_json(array)
    array.map { |item| item.transform_keys { |key| key.to_s.camelize(:lower) } }
  end

  # CAP is not bypassed here as AbstractChatController requires a logged in user
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  memoize def individual_access_enabled?
    Copilot::Policies::SpacesIndividualAccess.effective_value(Copilot::User.new(current_user)) == "enabled"
  end

  memoize def individual_sharing_enabled?
    Copilot::Policies::SpacesIndividualSharing.effective_value(Copilot::User.new(current_user)) == "enabled"
  end

  # Filters out user-owned spaces if individual access policy is disabled.
  sig { params(spaces: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
  def apply_individual_access_filter(spaces)
    return spaces if individual_access_enabled?

    # Remove includes to avoid EagerLoadPolymorphicError when plucking from polymorphic owner
    owner_ids = spaces.unscope(:includes).pluck(:owner_id).uniq
    user_type_ids = User.where(id: owner_ids, type: "User").pluck(:id)
    spaces.where.not(owner_id: user_type_ids)
  end

  # If individual sharing is disabled, removes spaces owned by other users that are not shareable.
  sig { params(spaces: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
  def apply_individual_sharing_filter(spaces)
    started_at = Time.now

    space_owner_ids = spaces.unscope(:includes).pluck(:owner_id).uniq
    space_owner_ids = space_owner_ids - [current_user.id]
    user_type_owner_ids = User.where(id: space_owner_ids, type: "User").pluck(:id)
    user_owned_spaces = spaces.where(owner_id: user_type_owner_ids)

    rejected_spaces = user_owned_spaces.to_a.select do |copilot|
      # for feature flag check
      copilot.current_user = current_user
      !copilot.shareable? && copilot.owner.id != current_user.id
    end

    result = spaces.where.not(id: rejected_spaces.map(&:id))

    elapsed_time_ms = (Time.now - started_at) * 1000
    CopilotSpaces::HydroEventsHelper.instrument_generic_event("spaces_apply_individual_sharing_filter", current_user, nil, data: {
      controller: self.class.name,
      elapsed_time_ms: elapsed_time_ms,
      user_owned_spaces_count: user_owned_spaces.count,
      rejected_count: rejected_spaces.count,
      total_spaces: spaces.count,
    })

    result
  end

  def assign_user_and_cap(copilot_space)
    copilot_space.current_user = current_user
    copilot_space.cap_filter = cap_filter
  end

  # Filter spaces to only those the user can edit using parallel async checks
  # Similar to how org_owned_spaces parallelize adminable_by? checks
  sig { params(spaces: T::Array[CopilotSpace]).returns(T::Array[CopilotSpace]) }
  def filter_editable_spaces_parallel(spaces)
    started_at = Time.now

    spaces.each { |space| assign_user_and_cap(space) }

    editable_promises = spaces.map { |space| space.async_editable_by?(current_user) }
    editable_results = Promise.all(editable_promises).sync

    editable_spaces = spaces.zip(editable_results).select { |_space, editable| editable }.map(&:first)

    elapsed_time_ms = (Time.now - started_at) * 1000
    CopilotSpaces::HydroEventsHelper.instrument_generic_event("filter_editable_spaces_parallel", current_user, nil, data: {
      controller: self.class.name,
      elapsed_time_ms: elapsed_time_ms,
      total_spaces: spaces.length,
      editable_spaces_count: editable_spaces.length,
    })

    editable_spaces
  end

  sig { params(spaces_relation: ActiveRecord::Relation, limit: Integer).returns(T::Array[CopilotSpace]) }
  def collect_editable_spaces(spaces_relation, limit)
    result = T.let([], T::Array[CopilotSpace])
    last_id = T.let(nil, T.nilable(Integer))

    # Use keyset pagination on the primary key (id) to avoid large OFFSET scans.
    base_relation = spaces_relation.reorder(:id)

    loop do
      scoped_relation = if last_id
        base_relation.where(base_relation.klass.arel_table[:id].gt(last_id))
      else
        base_relation
      end

      batch = scoped_relation.limit(EDITABLE_BATCH_SIZE).to_a
      break if batch.empty?

      editable = filter_editable_spaces_parallel(batch)
      result.concat(editable)

      break if result.size >= limit || batch.size < EDITABLE_BATCH_SIZE

      last_id = batch.last.id
    end

    result.first(limit)
  end

  # Filter spaces by user's role in each space
  sig { params(spaces: T::Array[CopilotSpace], role: String).returns(T::Array[CopilotSpace]) }
  def filter_spaces_by_role(spaces, role)
    target_roles = case role
    when "admin"
      ["custom_copilot_admin"]
    when "editor", "writer"
      %w[custom_copilot_admin custom_copilot_writer]
    when "reader"
      %w[custom_copilot_admin custom_copilot_writer custom_copilot_reader]
    else
      []
    end

    spaces.select do |space|
      # Include spaces owned by the user (they have implicit admin access)
      if space.owner == current_user
        true
      else
        # Check if user has any of the target roles for this space
        user_roles = space.user_roles.select { |ur| ur.actor_id == current_user.id && ur.actor_type == "User" }
        role_ids = user_roles.map(&:role_id)
        if role_ids.any?
          # Load the roles and check their names
          role_names = Role.where(id: role_ids).pluck(:name)
          (role_names & target_roles).any?
        else
          false
        end
      end
    end
  end

  # Builds the base scope for searching CopilotSpaces, including owner filtering.
  def build_spaces_scope_for_search(params)
    scope = if params[:type].present?
      # Type is used for searching from the spaces index page
      case params[:type]
      when "starred"
        starred_copilot_spaces
      when "user_owned"
        user_owned_copilot_spaces
      when "org_owned"
        org_owned_copilot_spaces
      when "shared_with_user"
        shared_with_me_copilot_spaces
      end
    end
    scope ||= CopilotSpace.visible_to(current_user, cap_filter)

    scope = apply_individual_access_filter(scope)

    scope = apply_individual_sharing_filter(scope)

    if params[:owner].present?
      owner_login = params[:owner]
      owner = User.find_by_login(owner_login)
      owners = owner ? [owner, current_user] : [current_user]
      scope = scope.where(owner: owners)
    end

    scope
  end

  # Serializes spaces for JSON response.
  def serialize_spaces(spaces)
    # Aggregate shareable checks per unique user owner to avoid N policy checks
    shareable_by_owner = compute_shareable_by_owner(spaces)

    spaces.map do |copilot|
      assign_user_and_cap(copilot)
      CopilotSpaces::PageData::CopilotSpace::IndexPayload.call(
        copilot,
        editable: true,
        adminable: true,
        shareable: shareable_by_owner[copilot.owner_id]
      ).as_json
    end
  end
end
