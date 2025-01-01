# typed: strict
# frozen_string_literal: true

class Api::OrganizationCampaigns < Api::App
  before do
    deliver_error! 404 if GitHub.enterprise?
  end

  get "/organizations/:organization_id/campaigns/:campaign_number", operation_id: "campaigns/get-campaign-summary" do
    org = ActiveRecord::Base.connected_to(role: :reading) { find_org! }

    deliver_error! 404 unless SecurityCampaigns.api_enabled?(org)

    control_access :read_campaign,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    campaign_number = int_id_param!(key: :campaign_number, halt: true)
    campaign = SecurityCampaigns::SecurityCampaign.published.
      includes(:user_manager_users, team_manager_teams: :organization).
      find_by(organization: org, number: campaign_number)
    deliver_error!(404, message: "Campaign not found") unless campaign

    campaign_with_counts = get_campaign_with_counts(campaign, org, current_user)

    deliver :organization_campaign_hash,
      { campaign: campaign, campaign_with_counts: campaign_with_counts }
  end

  get "/organizations/:organization_id/campaigns", operation_id: "campaigns/list-org-campaigns" do
    org = ActiveRecord::Base.connected_to(role: :reading) { find_org! }

    deliver_error! 404 unless SecurityCampaigns.api_enabled?(org)
    control_access :read_campaign,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_non_conflicting_cursor_params!

    campaigns = SecurityCampaigns::SecurityCampaign.published.
      where(organization: org).
      includes(:user_manager_users, team_manager_teams: :organization)

    # Filter by state
    if params[:state] == "open"
      campaigns = campaigns.open
    elsif params[:state] == "closed"
      campaigns = campaigns.closed
    else
      campaigns = campaigns.all
    end

    # Apply sorting
    sort_order = convert_api_sort_order(params[:sort])
    sort_direction = convert_api_sort_direction(params[:direction])
    campaigns = campaigns.order("#{sort_order} #{sort_direction}")

    # Paginate and get results
    campaigns = paginate_rel(campaigns).to_a
    campaigns_with_counts = get_campaigns_with_counts(campaigns, org, current_user)

    GitHub::PrefillAssociations.prefill_batch_method(campaigns.flat_map(&:team_manager_teams), :parent_team)

    # Serialize and return
    paginator.collection_size = campaigns.total_entries
    deliver :organization_campaigns_hash, { campaigns: campaigns, campaigns_with_counts: campaigns_with_counts }
  end

  post "/organizations/:organization_id/campaigns", operation_id: "campaigns/create-campaign" do
    org = ActiveRecord::Base.connected_to(role: :reading) { find_org! }

    deliver_error! 404 unless SecurityCampaigns.api_enabled?(org)

    control_access :write_campaign,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi

    org_campaigns_count = SecurityCampaigns::SecurityCampaign.open.where(organization_id: org.id).count
    if org_campaigns_count >= SecurityCampaigns::MAX_OPEN_CAMPAIGNS_COUNT
      deliver_error! 400, message: SecurityCampaigns::MAX_OPEN_CAMPAIGNS_CREATION_ERROR_MESSAGE, errors: [
        api_error(:Campaign, :count, :invalid)
      ]
    end

    managers = data["managers"] ? validate_managers!(managers: data["managers"], org:) : []
    team_managers = data["team_managers"] ? validate_team_managers!(team_managers: data["team_managers"], org:) : []

    validate_number_campaign_managers!(user_manager_ids: managers.map(&:id), team_manager_ids: team_managers.map(&:id))

    ends_at = validate_ends_at!(ends_at: data["ends_at"])
    code_scanning_alerts, repositories, repository_ids = validate_code_scanning_alerts!(code_scanning_alerts: data["code_scanning_alerts"], org:)

    repo_numbers = code_scanning_alerts.flat_map do |alerts|
      repository = repositories[alerts["repository_id"]]
      next if repository.nil?

      alerts["alert_numbers"].map do |alert_number|
        Turboscan::Proto::RepoNumber.new(
          repository_id: repository.id,
          number: alert_number,
        )
      end
    end

    alerts = begin
      turboscan_alerts(org:, repository_ids:, repo_numbers:)
    rescue
      deliver_error! 500, message: "Failed to fetch alerts to include in the campaign. Please try again."
    end

    if alerts.size != repo_numbers.size
      deliver_error! 422, message: "Failed to find all provided alerts."
    end

    logical_alert_info = T.let({}, T::Hash[Integer, T::Array[Turboscan::Proto::Result]])
    alerts.each do |alert|
      if !logical_alert_info.key?(alert.repository_id)
        logical_alert_info[alert.repository_id] = []
      end

      T.must(logical_alert_info[alert.repository_id]) << T.must(alert.result)
    end

    generate_issues = T.let(data["generate_issues"] == true, T::Boolean) && SecurityCampaigns.issue_creation_enabled?(org)

    campaign = begin
      opening_details = SecurityCampaigns::CampaignOpeningDetails.new(
        org:,
        name: data["name"],
        managers: managers,
        team_managers: team_managers,
        description: data["description"],
        ends_at: ends_at.to_time,
        contact_link: data["contact_link"],
        query_string: "",
        alerts: logical_alert_info,
        generate_issues:
      )
      SecurityCampaigns::CreationService.call(opening_details:, actor: current_user)
    rescue ActiveRecord::RecordNotSaved => e
      deliver_error! 400, message: e.message
    rescue ActiveRecord::RecordInvalid => e
      deliver_error! 422, message: e.message, errors: e.record.errors, resource: "Campaign"
    rescue SecurityCampaigns::TurboscanError
      deliver_error! 500, message: "An error occurred while creating the security campaign, please try again later."
    end

    deliver :organization_campaign_hash,
      { campaign: campaign } # The stats might not have been updated yet, so we don't include them here
  end

  patch "/organizations/:organization_id/campaigns/:campaign_number", operation_id: "campaigns/update-campaign" do
    org = ActiveRecord::Base.connected_to(role: :reading) { find_org! }

    deliver_error! 404 unless SecurityCampaigns.api_enabled?(org)

    control_access :write_campaign,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi

    campaign_number = int_id_param!(key: :campaign_number, halt: true)
    campaign = SecurityCampaigns::SecurityCampaign.
      published.
      includes(:user_manager_users, team_manager_teams: :organization).
      find_by(organization: org, number: campaign_number)
    deliver_error!(404, message: "Campaign not found") unless campaign

    if update_campaign!(data, campaign, org, current_user)
      SecurityCampaigns::UpdateIssuesJob.perform_later(campaign_id: campaign.id)

      campaign_with_counts = get_campaign_with_counts(campaign, org, current_user)
      deliver :organization_campaign_hash,
        { campaign: campaign, campaign_with_counts: campaign_with_counts }
    else
      deliver_error 422, message: "Validation failed", errors: campaign.errors, resource: "Campaign"
    end
  end

  delete "/organizations/:organization_id/campaigns/:campaign_number", operation_id: "campaigns/delete-campaign" do
    org = ActiveRecord::Base.connected_to(role: :reading) { find_org! }

    deliver_error! 404 unless SecurityCampaigns.api_enabled?(org)

    control_access :write_campaign,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    campaign_number = int_id_param!(key: :campaign_number, halt: true)
    campaign = SecurityCampaigns::SecurityCampaign.published.find_by(organization: org, number: campaign_number)
    deliver_error!(404, message: "Campaign not found") unless campaign

    begin
      SecurityCampaigns::DeletionService.call(campaign: campaign, actor: current_user)
      deliver_empty status: 204
    rescue ActiveRecord::RecordNotFound
      deliver_error! 404, message: "Campaign not found"
    rescue ActiveRecord::RecordNotDestroyed
      deliver_error! 422, message: "Unable to delete campaign"
    end
  end

  private

  sig { void }
  def ensure_non_conflicting_cursor_params!
    if params.key?(:after) && params.key?(:before)
      deliver_error!(400, message: "Please do not provide both 'before' and 'after' parameters.")
    end
  end

  sig { params(order: T.nilable(String)).returns(String) }
  def convert_api_sort_order(order)
    case order&.downcase
    when "created"
      "created_at"
    when "updated"
      "updated_at"
    when "ends_at"
      "ends_at"
    else
      "created_at"
    end
  end

  sig { params(direction: T.nilable(String)).returns(String) }
  def convert_api_sort_direction(direction)
    case direction&.downcase
    when "asc"
      "asc"
    when "desc"
      "desc"
    else
      "desc"
    end
  end

  sig { params(managers: T::Array[String], org: Organization).returns(T::Array[User]) }
  def validate_managers!(managers:, org:)
    managers = managers.compact_blank.uniq
    manager_users = User.with_logins(managers).index_by(&:display_login)
    potential_campaign_managers = SecurityCampaigns.potential_campaign_managers(org:)

    managers.map do |manager_login|
      manager = manager_users[manager_login]
      if manager.nil? || !potential_campaign_managers.include?(manager)
        deliver_error! 422, errors: [
          api_error(:Campaign, :managers, :invalid, value: manager_login)
        ]
      end
      manager
    end
  end

  sig { params(team_managers: T::Array[String], org: Organization).returns(T::Array[Team]) }
  def validate_team_managers!(team_managers:, org:)
    # The API spec validation guarantees that the number of team managers is less than the maximum
    team_manager_slugs = team_managers.compact_blank.uniq
    teams = Team.where(organization: org, slug: team_manager_slugs).index_by(&:slug)
    potential_campaign_manager_teams = SecurityCampaigns.potential_campaign_manager_teams(org:, current_user:)

    team_manager_slugs.map do |team_slug|
      team = teams[team_slug]
      if team.nil? || !potential_campaign_manager_teams.include?(team)
        deliver_error! 422, errors: [
          api_error(:Campaign, :team_managers, :invalid, value: team_slug)
        ]
      end
      team
    end
  end

  sig { params(user_manager_ids: T::Array[String], team_manager_ids: T::Array[String]).void }
  def validate_number_campaign_managers!(user_manager_ids:, team_manager_ids:)
    if (team_manager_ids.size + user_manager_ids.size) < 1
      deliver_error! 422, message: SecurityCampaigns::MIN_CAMPAIGN_MANAGER_ERROR_MESSAGE, errors: [
        api_error(:Campaign, :team_managers, :invalid)
      ]
    end
    if (team_manager_ids.size + user_manager_ids.size) > SecurityCampaigns::MAX_MANAGER_COUNT
      deliver_error! 422, message: SecurityCampaigns::MAX_CAMPAIGN_MANAGER_ERROR_MESSAGE, errors: [
        api_error(:Campaign, :team_managers, :invalid)
      ]
    end
  end

  sig { params(ends_at: String).returns(ActiveSupport::TimeWithZone) }
  def validate_ends_at!(ends_at:)
    ends_at = Time.zone.parse(ends_at)
    if ends_at.blank? || ends_at < Time.zone.now
      deliver_error! 422, errors: [
        api_error(:Campaign, :ends_at, :invalid)
      ]
    end

    ends_at
  end

  sig { params(code_scanning_alerts: T::Array[T::Hash[String, T.untyped]], org: Organization).returns(T::Array[T.untyped]) }
  def validate_code_scanning_alerts!(code_scanning_alerts:, org:)
    repository_ids = code_scanning_alerts.map { |alert| alert["repository_id"] }.uniq
    if repository_ids.size != code_scanning_alerts.size
      deliver_error! 422, message: "Each repository should only occur once.", errors: [
        api_error(:Campaign, :code_scanning_alerts, :invalid)
      ]
    end

    duplicate_alerts = code_scanning_alerts.any? do |alerts|
      alerts["alert_numbers"].size != alerts["alert_numbers"].uniq.size
    end
    if duplicate_alerts
      deliver_error! 422, message: "Each alert should only occur once.", errors: [
        api_error(:Campaign, :code_scanning_alerts, :invalid)
      ]
    end

    if repository_ids.size >= SecurityCampaigns::MAX_ALERTS_REPOSITORY_COUNT
      deliver_error! 422, message: "The limit on the number of repositories was exceeded.", errors: [
        api_error(:Campaign, :code_scanning_alerts, :invalid, max_repository_ids: SecurityCampaigns::MAX_ALERTS_REPOSITORY_COUNT)
      ]
    end

    code_scanning_alerts_count = code_scanning_alerts.sum { |alert| alert["alert_numbers"].size }
    if code_scanning_alerts_count > SecurityCampaigns::MAX_ALERTS_COUNT
      deliver_error! 422, message: "The limit on the number of alerts was exceeded.", errors: [
        api_error(:Campaign, :code_scanning_alerts, :invalid, max_alerts: SecurityCampaigns::MAX_ALERTS_COUNT)
      ]
    end

    repositories = ActiveRecord::Base.connected_to(role: :reading) do
      resolve_repositories(repository_ids:, org:).index_by(&:id)
    end

    if repositories.size != repository_ids.size
      invalid_repository_ids = repository_ids - repositories.keys
      deliver_error! 422, message: "Some of the supplied repositories could not be found.", errors: [
        api_error(:Campaign, :code_scanning_alerts, :invalid, not_found_repository_ids: invalid_repository_ids)
      ]
    end

    [code_scanning_alerts, repositories, repository_ids]
  end

  sig { params(repository_ids: T::Array[Integer], org: Organization).returns(T::Array[Repository]) }
  def resolve_repositories(repository_ids:, org:)
    repository_ids = Repositories::Public.filter_repo_ids_to_org(repo_ids: repository_ids, organization_id: org.id).pluck(:id)

    associated_repository_ids = find_associated_repository_ids(repository_ids, current_user)
    accessible_repositories = Repositories::Public.accessible_repositories(
      repository_ids: repository_ids, associated_repository_ids: associated_repository_ids
    )

    cap_filter.authorized_resources(accessible_repositories)
  end

  sig { params(repository_ids: T::Array[Integer], current_user: User).returns(T::Array[Integer]) }
  def find_associated_repository_ids(repository_ids, current_user)
    associated_repository_ids = Set.new(current_user.associated_repository_ids(min_action: :read, repository_ids: repository_ids))
    ProgrammaticActor::RepositoryFilter.perform(
      actor: current_user,
      repository_ids: associated_repository_ids,
      resource: "security_events",
    ).to_a
  end

  sig { params(org: Organization, repository_ids: T::Array[Integer], repo_numbers: T::Array[Turboscan::Proto::RepoNumber]).returns(T::Array[Turboscan::Proto::RepoResult]) }
  def turboscan_alerts(org:, repository_ids:, repo_numbers:)
    return [] if repo_numbers.empty?

    turboscan_alerts = T.let([], T::Array[Turboscan::Proto::RepoResult])

    repo_numbers.each_slice(SecurityCampaigns::TURBOSCAN_MAX_PAGE_SIZE) do |repo_numbers_slice|
      alerts_response = GitHub::Turboscan.alerts_by_repo({
        limit: SecurityCampaigns::TURBOSCAN_MAX_PAGE_SIZE,
        owner_ids: [org.id],
        repo_numbers: repo_numbers_slice,
        repository_ids:,
        state: :ALERT_STATE_FILTER_ALL,
      })

      raise StandardError.new(alerts_response&.error&.msg || "No response when fetching alerts") if alerts_response.nil? || alerts_response.error.present?

      alerts_response = alerts_response.data
      raise StandardError.new("No data when fetching alerts") if alerts_response.nil?

      page_turboscan_alerts = alerts_response.results.to_a
      turboscan_alerts += page_turboscan_alerts
    end

    turboscan_alerts
  end

  sig { params(data: T::Hash[String, T.untyped], campaign: SecurityCampaigns::SecurityCampaign, org: Organization, user: User).returns(T.nilable(T::Boolean)) }
  def update_campaign!(data, campaign, org, user)
    validate_campaign_update_input!(data, campaign)

    if campaign.open? && data["state"] == "closed"
      SecurityCampaigns::ClosureService.call(campaign:, actor: user, org:)
    elsif campaign.closed? && data["state"] == "open"
      begin
        SecurityCampaigns::ReopeningService.call(campaign:, org:, actor: user)
      rescue ActiveRecord::RecordNotSaved, ActiveRecord::Rollback => e
        deliver_error!(400, message: e.message)
      end
    end

    update_params = {}
    update_params[:name] = data["name"] if data["name"]
    update_params[:description] = data["description"] if data["description"]

    if data["ends_at"]
      ends_at = validate_ends_at!(ends_at: data["ends_at"])
      update_params[:ends_at] = ends_at
    end

    if data["managers"]
      managers = validate_managers!(managers: data["managers"], org: org)
      update_params[:user_manager_users] = managers
    end

    if data["team_managers"]
      team_managers = validate_team_managers!(team_managers: data["team_managers"], org:)
      update_params[:team_manager_teams] = team_managers
    end

    if data.key?("contact_link")
      update_params[:contact_link] = data["contact_link"]
    end

    if update_params[:user_manager_users] || update_params[:team_manager_teams]
      user_managers = update_params[:user_manager_users] || campaign.user_manager_users
      team_managers = update_params[:team_manager_teams] || campaign.team_manager_teams
      validate_number_campaign_managers!(user_manager_ids: user_managers.map(&:id), team_manager_ids: team_managers.map(&:id))
    end

    campaign.update(update_params)
  end

  sig { params(data: T::Hash[String, T.untyped], campaign: SecurityCampaigns::SecurityCampaign).void }
  def validate_campaign_update_input!(data, campaign)
    if data["state"]
      if data["state"] == "open" && campaign.open?
        deliver_error!(422, message: "Cannot open an already open campaign")
      elsif data["state"] == "closed" && campaign.closed?
        deliver_error!(422, message: "Cannot close an already closed campaign")
      end
    end

    campaign_being_edited = (data.keys - ["state"]).any? { |key| data[key] }
    campaign_closed_and_not_being_opened = campaign.closed? && data["state"] != "open"

    if campaign_being_edited && campaign_closed_and_not_being_opened
      deliver_error!(422, message: "Cannot edit a closed campaign")
    end
  end

  sig { params(campaign: SecurityCampaigns::SecurityCampaign, org: Organization, current_user: User).returns(T.nilable(SecurityCampaigns::CampaignWithCounts)) }
  def get_campaign_with_counts(campaign, org, current_user)

    get_campaigns_with_counts([campaign], org, current_user).first
  end

  sig { params(campaigns: T::Array[SecurityCampaigns::SecurityCampaign], org: Organization, current_user: User).returns(T::Array[SecurityCampaigns::CampaignWithCounts]) }
  def get_campaigns_with_counts(campaigns, org, current_user)

    # If this is a request where the actor has programmatic granular
    # permissions, filter the repositories before we send the request.
    programmatic_actor_grant = ProgrammaticActor::Grant.with(current_user).with_target(org)

    repository_ids = if programmatic_actor_grant && !programmatic_actor_grant.installed_on_all_repositories?
      programmatic_actor_grant.repository_ids(min_action: :read, resource: "security_events")
    end

    if repository_ids.is_a?(Array) && repository_ids.empty?
      return []
    end

    query_service = CodeScanning::AlertQueryService.for_organization(
      user: current_user,
      user_session: nil,
      organization: org,
      allowed_repository_ids: repository_ids,
      security_campaign_ids: campaigns.map(&:id).to_a
    )

    SecurityCampaigns::CampaignWithCounts.load(security_campaigns: campaigns, query_service:, user: current_user)
  end
end
