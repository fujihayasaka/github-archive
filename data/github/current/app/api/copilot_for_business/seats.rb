# typed: true
# frozen_string_literal: true

class Api::CopilotForBusiness::Seats < Api::App
  include FeatureFlagHelper
  include ReceiveSchemaWithOpenApi

  DOCS_BASE_URL = GitHub::Config::DOCS_BASE_URL
  CFB_DOCS_URL = "#{DOCS_BASE_URL}/copilot/about-github-copilot/subscription-plans-for-github-copilot"
  ACCESS_CONFIG_DOCS = "#{DOCS_BASE_URL}/copilot/managing-copilot/managing-github-copilot-in-your-organization/managing-access-to-github-copilot-in-your-organization/granting-access-to-copilot-for-members-of-your-organization#granting-access-to-github-copilot-for-specific-users-in-your-organization"
  COPILOT_ORG_BILLING_DOCS = "#{DOCS_BASE_URL}/billing/managing-billing-for-github-copilot/managing-your-github-copilot-subscription-for-your-organization-or-enterprise#setting-up-a-copilot-business-subscription-for-your-organization"
  COPILOT_ENTERPRISE_BILLING_DOCS = "#{DOCS_BASE_URL}/copilot/managing-copilot/managing-copilot-for-your-enterprise/managing-the-copilot-subscription-for-your-enterprise/about-billing-for-github-copilot-in-your-enterprise"
  AZURE_BILLING_DOCS = "#{DOCS_BASE_URL}/github/setting-up-and-managing-billing-and-payments-on-github/connecting-an-azure-subscription-to-your-enterprise"
  SUGGESTIONS_CONFIG_DOCS = "#{DOCS_BASE_URL}/copilot/managing-copilot/managing-github-copilot-in-your-organization/managing-policies-for-copilot-in-your-organization#policies-for-suggestion-matching"

  # default number of seats returned per page from list seats endpoint
  DEFAULT_PER_PAGE = 50

  get "/organizations/:organization_id/members/:user_id/copilot", operation_id: "copilot/get-copilot-seat-details-for-user" do
    @route_owner = "@github/heart-services"
    ensure_endpoint_enabled

    org = find_org!
    user = find_user!

    control_access :copilot_org_seat_management_reader,
      resource: org,
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      enforce_oauth_app_policy: true

    receive_with_openapi

    deliver_error!(422, message: "User has a pending organization invitation.") if org.pending_invitation_for(user)
    deliver_error!(404, message: "User does not exist in this organization.") unless org.member_ids.include?(T.must(user).id)

    copilot_org = Copilot::Organization.new(org)

    deliver_error!(404, message: "No seat found for this user in this organization.", documentation_url: ACCESS_CONFIG_DOCS) if !copilot_org.has_seat_for?(T.must(user))

    seat, usage_detail = find_seat_and_usage!(user, org)

    deliver :copilot_seat_detail_hash, { plan_type: Copilot::Organization.new(org).copilot_plan, assignee: user, seat: seat, usage_detail: usage_detail }, global_id_selection: global_id_selection
  end

  get "/enterprises/:enterprise_id/members/:user_id/copilot", operation_id: "copilot/get-copilot-seat-details-for-enterprise-user" do
    ensure_endpoint_enabled

    enterprise = find_enterprise!
    user = find_user!

    deliver_error!(404, documentation_url: "#{DOCS_BASE_URL}/rest") unless enterprise&.can_assign_copilot_to_business_users?

    control_access :copilot_enterprise_seat_management_reader,
      resource: enterprise,
      allow_user_via_granular_actor: false, # FGP will be added later along with the rest of these Copilot endpoints
      allow_integrations: false,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_ADMIN_FORBID_MESSAGE

    receive_with_openapi

    copilot_biz = Copilot::Business.new(enterprise)

    deliver_error!(404, message: "User does not exist in this enterprise.") unless enterprise.user_accounts.find_by(user_id: user.id).present?
    deliver_error!(404, message: "No seat found for this user in this enterprise.", documentation_url: ACCESS_CONFIG_DOCS) if !copilot_biz.has_seat_for?(T.must(user))

    seats = Copilot::Seat.for_business_user(enterprise, user)

    deduped_seat_count = seats.uniq(&:assigned_user_id).count # This should always be 1, but dedup to be sure
    plan_types = Copilot::Seat.seat_plan_types_by_owner_type(seats)

    deliver :copilot_seats_list_hash, { plan_types: plan_types, count: deduped_seat_count, seats: seats, enterprise: true }, global_id_selection: global_id_selection
  end

  post "/organizations/:organization_id/copilot/billing/selected_users", operation_id: "copilot/add-copilot-seats-for-users" do
    @route_owner = "@github/heart-services"
    ensure_endpoint_enabled

    org = find_org!

    control_access :copilot_org_seat_management_writer,
      resource: org,
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi

    copilot_org = Copilot::Organization.new(org)
    ensure_cfb_setup(copilot_org)

    selected_users = find_selected_users!(org, data["selected_usernames"])

    total_seats = 0

    selected_users.each do |user|
      existing_seat_assignment = Copilot::SeatAssignment.find_by(assignable_id: user.id, owner_id: org.id)

      if existing_seat_assignment.present? && !existing_seat_assignment.pending_cancellation?
        GitHub.logger.info(
          "Found existing SeatAssignment not pending cancellation for user",
          "gh.copilot.seat_assignment.id" => existing_seat_assignment.id,
          "gh.copilot.seat_assignment.assignable_type" => existing_seat_assignment.assignable_type,
          "gh.copilot.seat_assignment.assignable.id" => existing_seat_assignment.assignable_id,
          "gh.copilot.seat_assignment.owner.id" => existing_seat_assignment.owner_id
        )
        next
      end

      result = copilot_org.assign([T.must(user)], current_user)
      handle_seat_error(result, user, "created") if result.error

      seat_assignment = result.value!.first
      seat_assignment.convert_to_seats
      total_seats += 1
    end

    deliver :total_seats_hash, { seat_count: total_seats }, created: true, status: 201
  end

  post "/enterprises/:enterprise_id/copilot/billing/selected_users", operation_id: "copilot/add-copilot-seats-for-enterprise-users" do
    ensure_endpoint_enabled

    enterprise = find_enterprise!

    deliver_error!(404, documentation_url: "#{DOCS_BASE_URL}/rest") unless enterprise&.can_assign_copilot_to_business_users?

    control_access :copilot_enterprise_seat_management_writer,
      resource: enterprise,
      allow_user_via_granular_actor: false, # FGP will be added later along with the rest of these Copilot endpoints
      allow_integrations: false,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_ADMIN_FORBID_MESSAGE

    data = receive_with_openapi

    copilot_business = Copilot::Business.new(enterprise)
    ensure_business_billable(copilot_business)
    ensure_copilot_enabled(copilot_business)

    selected_users = find_selected_business_users!(enterprise, data["selected_usernames"])

    total_seats = 0

    selected_users.each do |user|
      existing_seat_assignment = Copilot::SeatAssignment.find_by(assignable_id: user.id, owner_id: enterprise.id)

      if existing_seat_assignment.present? && !existing_seat_assignment.pending_cancellation?
        GitHub.logger.info(
          "Found existing SeatAssignment not pending cancellation for user",
          "gh.copilot.seat_assignment.id" => existing_seat_assignment.id,
          "gh.copilot.seat_assignment.assignable_type" => existing_seat_assignment.assignable_type,
          "gh.copilot.seat_assignment.assignable.id" => existing_seat_assignment.assignable_id,
          "gh.copilot.seat_assignment.owner_id" => existing_seat_assignment.owner_id
        )
        next
      end

      result = copilot_business.assign([T.must(user)], current_user)
      handle_seat_error(result, user, "created") if result.error

      seat_assignment = result.value!.first
      seat_assignment.convert_to_seats
      total_seats += 1
    end

    deliver :total_seats_hash, { seat_count: total_seats }, created: true, status: 201
  end

  delete "/enterprises/:enterprise_id/copilot/billing/selected_users", operation_id: "copilot/cancel-copilot-seats-for-enterprise-users" do
    ensure_endpoint_enabled

    enterprise = find_enterprise!

    deliver_error!(404, documentation_url: "#{DOCS_BASE_URL}/rest") unless enterprise&.can_assign_copilot_to_business_users?

    control_access :copilot_enterprise_seat_management_writer,
      resource: enterprise,
      allow_user_via_granular_actor: false, # FGP will be added later along with the rest of these Copilot endpoints
      allow_integrations: false,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_ADMIN_FORBID_MESSAGE

    data = receive_with_openapi

    copilot_business = Copilot::Business.new(enterprise)
    ensure_business_billable(copilot_business)
    ensure_copilot_enabled(copilot_business)

    selected_users = find_selected_business_users!(enterprise, data["selected_usernames"])

    total_seats = 0

    selected_users.each do |user|
      seat = Copilot::Seat.for_assignable_in_business(user, enterprise)

      deliver_error!(422, message: "Seat assignment could not be cancelled: user #{user.display_login} was assigned via team #{T.must(T.must(seat).seat_assignment).assignable.name}.") if seat && T.must(seat.seat_assignment).assignable_type == "Team"

      result = copilot_business.unassign([T.must(user)], current_user)
      handle_seat_error(result, user, "cancelled") if result.error
      total_seats += 1
    end

    deliver :total_seats_hash, { seat_count: total_seats }
  end

  post "/organizations/:organization_id/copilot/billing/selected_teams", operation_id: "copilot/add-copilot-seats-for-teams" do
    @route_owner = "@github/heart-services"
    ensure_endpoint_enabled

    org = find_org!

    control_access :copilot_org_seat_management_writer,
      resource: org,
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi

    copilot_org = Copilot::Organization.new(org)
    ensure_cfb_setup(copilot_org)

    selected_teams = find_selected_teams!(org, data["selected_teams"])

    total_seats = 0

    selected_teams.each do |team|
      existing_seat_assignment = Copilot::SeatAssignment.find_by(assignable_id: team.id, owner_id: org.id)
      if existing_seat_assignment.present? && !existing_seat_assignment.pending_cancellation?
        GitHub.logger.info(
          "Found existing SeatAssignment not pending cancellation for team",
          "gh.copilot.seat_assignment.id" => existing_seat_assignment.id,
          "gh.copilot.seat_assignment.assignable_type" => existing_seat_assignment.assignable_type,
          "gh.copilot.seat_assignment.assignable.id" => existing_seat_assignment.assignable_id,
          "gh.copilot.seat_assignment.owner.id" => existing_seat_assignment.owner_id
        )
        next
      end

      result = copilot_org.assign([T.must(team)], current_user)
      handle_seat_error(result, team, "created") if result.error

      seat_assignment = result.value!.first
      seat_assignment.convert_to_seats

      total_seats += seat_assignment.assignable_count
    end

    deliver :total_seats_hash, { seat_count: total_seats }, created: true, status: 201
  end

  delete "/organizations/:organization_id/copilot/billing/selected_users", operation_id: "copilot/cancel-copilot-seat-assignment-for-users" do
    @route_owner = "@github/heart-services"
    ensure_endpoint_enabled

    org = find_org!

    control_access :copilot_org_seat_management_writer,
      resource: org,
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi

    copilot_org = Copilot::Organization.new(org)
    ensure_cfb_setup(copilot_org)

    selected_users = find_selected_users!(org, data["selected_usernames"])

    total_seats = 0

    selected_users.each do |user|
      seat = Copilot::Seat.for_assignable_in_org(user.id, org)

      deliver_error!(422, message: "Seat assignment could not be cancelled: user #{user.display_login} was assigned via team #{T.must(T.must(seat).seat_assignment).assignable.name}.") if seat && T.must(seat.seat_assignment).assignable_type == "Team"

      # don't re-cancel this person's seat or count them towards total seats cancelled
      next if seat && T.must(seat.seat_assignment).pending_cancellation?

      result = copilot_org.unassign([T.must(user)], current_user)
      handle_seat_error(result, user, "cancelled") if result.error
      total_seats += 1
    end

    deliver :total_seats_hash, { seat_count: total_seats }
  end

  delete "/organizations/:organization_id/copilot/billing/selected_teams", operation_id: "copilot/cancel-copilot-seat-assignment-for-teams" do
    @route_owner = "@github/heart-services"
    ensure_endpoint_enabled

    org = find_org!

    control_access :copilot_org_seat_management_writer,
      resource: org,
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi

    copilot_org = Copilot::Organization.new(org)
    ensure_cfb_setup(copilot_org)

    selected_teams = find_selected_teams!(org, data["selected_teams"])

    total_seats = 0

    selected_teams.each do |team|
      assignment = Copilot::SeatAssignment.find_by(
        assignable_id: team.id,
        assignable_type: "Team",
        owner_id: org.id,
      )

      # don't re-cancel this team's assignment or count the members towards total seats cancelled
      next if assignment && assignment.pending_cancellation?

      result = copilot_org.unassign([T.must(team)], current_user)
      handle_seat_error(result, team, "cancelled") if result.error

      total_seats += T.must(assignment).assignable_count
    end

    deliver :total_seats_hash, { seat_count: total_seats }
  end

  get "/organizations/:organization_id/copilot/billing", operation_id: "copilot/get-copilot-organization-details" do
    @route_owner = "@github/heart-services"
    ensure_endpoint_enabled

    org = find_org!

    control_access :copilot_org_seat_management_reader,
      resource: org,
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      enforce_oauth_app_policy: true

    deliver :copilot_entity_summary_hash, { entity: org, current_user: current_user }
  end

  get "/organizations/:organization_id/copilot/billing/seats", operation_id: "copilot/list-copilot-seats" do
    @route_owner = "@github/heart-services"
    ensure_endpoint_enabled

    org = find_org!

    control_access :copilot_org_seat_management_reader,
      resource: org,
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      enforce_oauth_app_policy: true

    if org.feature_enabled?(:copilot_api_max_pagination)
      cap_paginated_entries! 250_000
      @paginator = build_paginator(default_per_page: 50, max_per_page: 1000)
    end

    seats = Copilot::Seat.for_organization(org)
    seat_count = seats.count

    paginated_seats = get_paginated_seats(seats, seat_count)
    plan_types = Copilot::Seat.seat_plan_types_by_owner_type(paginated_seats)

    deliver :copilot_seats_list_hash, { plan_types: plan_types, count: seat_count, seats: paginated_seats }, global_id_selection: global_id_selection
  end

  get "/enterprises/:enterprise_id/copilot/billing/seats", operation_id: "copilot/list-copilot-seats-for-enterprise" do
    @route_owner = "@github/heart-services"
    ensure_endpoint_enabled

    enterprise = find_enterprise!

    control_access :copilot_enterprise_seat_management_reader,
      resource: enterprise,
      allow_user_via_granular_actor: false,
      allow_integrations: false

    if enterprise.feature_enabled?(:copilot_api_max_pagination)
      cap_paginated_entries! 250_000
      @paginator = build_paginator(default_per_page: 50, max_per_page: 1000)
    end

    seats = Copilot::Seat.for_business(enterprise)

    # this is the total_seats number we return in the response, and the number of seats we are actually billing for
    deduped_seat_count = seats.uniq(&:assigned_user_id).count

    # we still need the total number of seats in the seats array, for pagination
    total_seat_count = seats.count
    paginated_seats = get_paginated_seats(seats, total_seat_count)

    plan_types = Copilot::Seat.seat_plan_types_by_owner_type(paginated_seats)

    deliver :copilot_seats_list_hash, { plan_types: plan_types, count: deduped_seat_count, seats: paginated_seats, enterprise: true }, global_id_selection: global_id_selection
  end

  get "/enterprises/:enterprise_id/copilot/billing", operation_id: "copilot/get-copilot-enterprise-details" do
    @route_owner = "@github/heart-services"
    ensure_endpoint_enabled

    enterprise = find_enterprise!

    deliver_error!(404, documentation_url: "#{DOCS_BASE_URL}/rest") unless enterprise&.feature_enabled?(:copilot_enterprise_info_endpoint)

    control_access :copilot_enterprise_seat_management_reader,
      resource: enterprise,
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_ADMIN_FORBID_MESSAGE

    receive_with_openapi

    deliver :copilot_entity_summary_hash, { entity: enterprise, current_user: current_user }
  end

  private

  def get_paginated_seats(seats, seat_count)
    paginated_seats = paginate_rel(seats)

    # this is needed because we are using total_seats instead of total_count in the delivered hash
    paginator.collection_size = seat_count

    last_page = (seat_count / per_page.to_f).ceil
    if seat_count > per_page
      @links.add_current({ page: last_page }, rel: "last") if current_page != last_page
      @links.add_current({ page: current_page + 1 }, rel: "next") if current_page < last_page
      if current_page && current_page > 1
        @links.add_current({ page: 1 }, rel: "first")
        prev_page = (current_page <= last_page) ? current_page - 1 : 1
        @links.add_current({ page: prev_page }, rel: "prev")
      end
    end

    paginated_seats
  end

  def find_seat_and_usage!(user, org)
    # we checked before calling this method that the user is a member of the org and has a seat
    seat = T.must(Copilot::Seat.for_assignable_in_org(user.id, org))
    usage_detail = (org.feature_enabled?(:copilot_activity_api) || user.feature_enabled?(:copilot_activity_api)) ? Copilot::Activity.for_seat(seat) : Copilot::AggregateUsageDetail.latest_for_users(user)

    [seat, usage_detail]
  end

  def ensure_endpoint_enabled
    disabled = GitHub.enterprise?
    deliver_error!(404, documentation_url: "#{DOCS_BASE_URL}/rest") if disabled
  end

  def ensure_cfb_setup(copilot_org)
    ensure_cfb_enabled(copilot_org)
    ensure_org_billable(copilot_org)

    deliver_error!(422, message: "An organization owner must configure a public code suggestions policy for this organization.", documentation_url: SUGGESTIONS_CONFIG_DOCS) if copilot_org.no_public_code_suggestions_policy? || !copilot_org.public_code_suggestions_configured?

    deliver_error!(422, message: "Your organization has access to GitHub Copilot but has not configured its user access policy. Enable access for selected members in order to manage seats via the API.", documentation_url: ACCESS_CONFIG_DOCS) if copilot_org.seat_management_unconfigured?

    deliver_error!(422, message: "Your organization has enabled Copilot access for all members. Enable access for selected members in order to manage seats via the API.", documentation_url: ACCESS_CONFIG_DOCS) if copilot_org.seat_management_enabled_for_all?

    deliver_error!(422, message: "Your organization has disabled Copilot access for all members. Enable access for selected members in order to manage seats via the API.", documentation_url: ACCESS_CONFIG_DOCS) if copilot_org.seat_management_disabled?
  end

  def ensure_cfb_enabled(copilot_org)
    deliver_error!(422, message: "#{Copilot.business_product_name} is not enabled for this organization.", documentation_url: CFB_DOCS_URL) if copilot_org.copilot_disabled? || !copilot_org.copilot_for_business_enabled?
  end

  def ensure_org_billable(copilot_org)
    deliver_error!(422, message: "There is a problem with the payment method associated with this account. Please check your account settings.", documentation_url: COPILOT_ORG_BILLING_DOCS) if !copilot_org.copilot_billable? && !copilot_org.on_free_trial?
  end

  def ensure_copilot_enabled(copilot_business)
    deliver_error!(422, message: "#{Copilot.business_product_name} is not enabled for this enterprise.", documentation_url: CFB_DOCS_URL) if copilot_business.copilot_disabled?
  end

  def ensure_business_billable(copilot_business)
    docs_link = copilot_business.is_standalone_business? ? AZURE_BILLING_DOCS : COPILOT_ENTERPRISE_BILLING_DOCS
    deliver_error!(422, message: "There is a problem with the payment method associated with this account. Please check your account settings.", documentation_url: docs_link) if !copilot_business.copilot_billable?
  end

  def find_selected_users!(org, selected_usernames)
    users = GitHub.multi_tenant_enterprise? ? org.members.where(display_login: selected_usernames, business_id: org.business.id) : org.members.where(login: selected_usernames)

    usernames_in_db = users.map { |u| u.display_login.downcase }
    non_members = selected_usernames.select do |username|
      !usernames_in_db.include?(username.downcase)
    end

    deliver_error!(404, message: "One or more users do not exist in this organization: #{non_members.join(", ")}") if !non_members.empty?
    users.to_a
  end

  def find_selected_business_users!(business, selected_usernames)
    users = business.user_accounts.where(login: selected_usernames)
    usernames_in_db = users.map { |u| u.display_login.downcase }
    non_members = selected_usernames.select do |username|
      !usernames_in_db.include?(username.downcase)
    end
    deliver_error!(404, message: "One or more users do not exist in this enterprise: #{non_members.join(", ")}") if !non_members.empty?
    # we need to return the user objects, not the business_user objects
    users.map(&:user).to_a
  end

  def find_selected_teams!(org, selected_teams)
    teams = org.teams.where(name: selected_teams)

    team_names_in_db = teams.map { |t| t.name.downcase }
    non_teams = selected_teams.select do |team_name|
      !team_names_in_db.include?(team_name.downcase)
    end

    deliver_error!(404, message: "One or more teams do not exist in this organization: #{non_teams.join(", ")}") if !non_teams.empty?
    teams.each do |team|
      # not sure this is possible but let's catch it anyway
      deliver_error!(404, message: "Team #{team.name} has no members") if team.member_ids.empty?
    end
    teams.to_a
  end

  def handle_seat_error(result, assignable, verb)
    assignable_identifier = case assignable
    when User
      "user #{assignable.display_login}"
    when Team
      "team #{assignable.name}"
    end

    deliver_error!(500, message: "Seat assignment for #{assignable_identifier} could not be #{verb}.") unless result.error.is_a?(Copilot::Errors::SeatAssignmentError)

    deliver_error!(422, message: "Seat assignment for #{assignable_identifier} could not be #{verb}: #{result.error.message}")
  end
end
