# typed: true
# frozen_string_literal: true

class Copilot::Chat::CopilotSpacesController < Copilot::Chat::AbstractChatController
  allow_verified_fetch only: [:index, :search]
  before_action :require_copilot_spaces_feature_enabled

  # Maximum number of search results to return from the API
  SEARCH_RESULTS_LIMIT = 10

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
    spaces = filtered_copilot_spaces_by_type

    perf_experiment = FeatureFlag.vexi.enabled?(:copilot_spaces_server_side_menu_actions_backend, current_user, default: false)
    unless perf_experiment
      editable_promises = spaces.map do |copilot|
        copilot.async_editable_by?(current_user)
      end
      adminable_promises = spaces.map do |copilot|
        copilot.async_adminable_by?(current_user)
      end

      editable_results = Promise.all(editable_promises).sync
      adminable_results = Promise.all(adminable_promises).sync
    end

    json = spaces.map.with_index do |copilot, index|
      assign_user_and_cap(copilot)
      CopilotSpaces::PageData::CopilotSpace::IndexPayload.call(
        copilot,
        editable: perf_experiment ? true : editable_results[index],
        adminable: perf_experiment ? true : adminable_results[index]
      ).as_json
    end
    render json: to_camel_case_json(json)
  end


  # TODO: Example of how to use CopilotSpaces::Pagination module:
  # include CopilotSpaces::Pagination
  #
  # def paginated_index
  #   per_page = parse_per_page(params)
  #   current_cursor = parse_pagination_cursor(params, per_page)
  #   spaces_plus_one = find_spaces_for_owner(some_scope, current_cursor)
  #   pagination_result = calculate_pagination_response(spaces_plus_one, current_cursor, per_page)
  #
  #   # Set pagination headers if needed
  #   if request.present? && response.present?
  #     link_header = generate_pagination_link_header(pagination_result[:cursors], per_page, request.url.split("?").first)
  #     response.headers["Link"] = link_header if link_header
  #   end
  #
  #   # Use pagination_result[:spaces] for your response
  #   render json: pagination_result[:spaces]
  # end

  def count # rubocop:disable GitHub/UseRestfulActions
    render json: {
      shared_with_me_spaces: shared_with_me_copilot_spaces.count,
      org_owned_spaces: org_owned_copilot_spaces.count,
      user_owned_spaces: user_owned_copilot_spaces.count,
      starred_spaces: starred_copilot_spaces.count,
    }
  end

  def search # rubocop:disable GitHub/UseRestfulActions
    return render_404 unless FeatureFlag.vexi.enabled?(:copilot_spaces_search, current_user, default: false)

    spaces_scope = build_spaces_scope_for_search(params)
    filter_to_editable = params[:editable_only] == "true"

    query = params[:q]&.strip
    if query.blank?
      spaces = filter_to_editable ? filter_editable_spaces(spaces_scope.to_a) : spaces_scope.to_a
      spaces = spaces.first(SEARCH_RESULTS_LIMIT)
      spaces = filter_unprotected_spaces(spaces)
      return render json: to_camel_case_json(serialize_spaces(spaces))
    end

    return render json: { error: "Query too long" }, status: :bad_request if query.length > 100

    spaces_scope = spaces_scope.where("name LIKE ?", "%#{query.downcase}%")
    spaces = spaces_scope.to_a
    spaces = filter_unprotected_spaces(spaces)
    spaces = filter_editable_spaces(spaces) if filter_to_editable
    spaces = spaces.first(SEARCH_RESULTS_LIMIT)

    render json: to_camel_case_json(serialize_spaces(spaces))
  end

  def show
    started_at = Time.now
    copilot_space = if params[:owner].present? && params[:number].present?
      if FeatureFlag.vexi.enabled?(:copilot_spaces_read_access_to_user_owned_spaces, current_user, default: false)
        CopilotSpace.for_owner_login_and_number_with_user_roles!(params[:owner], params[:number])
      else
        CopilotSpace.for_owner_login_and_number!(params[:owner], params[:number])
      end
    else
      if FeatureFlag.vexi.enabled?(:copilot_spaces_read_access_to_user_owned_spaces, current_user, default: false)
        # We need user_roles to determine if the space is accessible because it has collaborators or is a public space
        CopilotSpace.includes(:user_roles).find_by!(id: params[:id])
      else
        CopilotSpace.find_by!(id: params[:id])
      end
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
    CopilotSpace.starred_by(current_user)
  end

  memoize def user_owned_copilot_spaces
    CopilotSpace.owned_by_user(current_user)
  end

  memoize def org_owned_copilot_spaces
    CopilotSpace.org_owned_spaces(current_user, cap_filter)
  end

  memoize def shared_with_me_copilot_spaces
    CopilotSpace.shared_with_user_spaces(current_user)
  end

  # Returns copilot spaces filtered by the type parameter
  # @return [Array<CopilotSpace>] filtered list of copilot spaces
  def filtered_copilot_spaces_by_type
    return copilot_spaces unless FeatureFlag.vexi.enabled?(:copilot_spaces_split_index_calls, current_user, default: false)

    case params[:type]
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

  def assign_user_and_cap(copilot_space)
    copilot_space.current_user = current_user
    copilot_space.cap_filter = cap_filter
  end

  # Filter spaces to only those the user can edit (has editor or admin role)
  sig { params(spaces: T::Array[CopilotSpace]).returns(T::Array[CopilotSpace]) }
  def filter_editable_spaces(spaces)
    spaces.select do |space|
      assign_user_and_cap(space)
      space.editable_by?(current_user)
    end
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
    scope = CopilotSpace.visible_query(current_user, cap_filter, nil)
      .includes(:owner, :resources, :user_roles)
      .order(:name)

    if params[:owner].present?
      owner_login = params[:owner]
      owner = User.find_by_login(owner_login)
      owners = owner ? [owner, current_user] : [current_user]
      scope = scope.where(owner: owners)
    end

    scope
  end

  # Filters out spaces with protected organizations.
  def filter_unprotected_spaces(spaces)
    spaces.reject { |space| space.protected_organizations(cap_filter: cap_filter).any? }
  end

  # Serializes spaces for JSON response.
  def serialize_spaces(spaces)
    spaces.map do |copilot|
      assign_user_and_cap(copilot)
      CopilotSpaces::PageData::CopilotSpace::IndexPayload.call(copilot).as_json
    end
  end
end
