# typed: strict
# frozen_string_literal: true

class Api::OrganizationCampaigns < Api::App
  DEFAULT_PER_PAGE = 5
  MAX_PER_PAGE = 10

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
    campaign = SecurityCampaigns::SecurityCampaign.find_by(organization: org, number: campaign_number)
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

    campaigns = SecurityCampaigns::SecurityCampaign.where(organization: org)

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

    repository_ids = ActiveRecord::Base.connected_to(role: :reading) do
      campaign_repository_ids = SecurityCampaigns::SecurityCampaignAlert.where(security_campaign_id: campaigns.pluck(:id)).distinct.pluck(:repository_id)
      resolve_repositories(repository_ids: campaign_repository_ids, org:).pluck(:id)
    end

    query_service = CodeScanning::AlertQueryService.for_organization(
      user: current_user,
      user_session: nil,
      organization: org,
      allowed_repository_ids: repository_ids,
    )

    campaigns_with_counts = SecurityCampaigns::CampaignWithCounts.load(security_campaigns: campaigns, query_service:, user: current_user)

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
    if org_campaigns_count >= SecurityCampaigns::MAX_CAMPAIGNS_COUNT
      deliver_error! 400, message: SecurityCampaigns::MAX_CAMPAIGNS_CREATION_ERROR_MESSAGE, errors: [
        api_error(:Campaign, :count, :invalid)
      ]
    end

    manager = validate_manager!(managers: data["managers"], org:)
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

    campaign = begin
      new_campaign = SecurityCampaigns::SecurityCampaign.new(
        organization: org,
        name: data["name"],
        manager:,
        description: data["description"],
        ends_at:,
      )
      SecurityCampaigns::CreationService.call(campaign: new_campaign, logical_alert_info:, actor: current_user, query_string: "")
    rescue ActiveRecord::RecordNotSaved => e
      deliver_error! 400, message: e.message
    rescue ActiveRecord::RecordInvalid => e
      deliver_error! 422, message: e.message, errors: e.record.errors
    end

    query_service = CodeScanning::AlertQueryService.for_organization(
      user: current_user,
      user_session: nil,
      organization: org,
      allowed_repository_ids: repository_ids,
    )

    campaign_with_counts = SecurityCampaigns::CampaignWithCounts.load(security_campaigns: [campaign], query_service:, user: current_user).first

    deliver :organization_campaign_hash,
      { campaign: campaign, campaign_with_counts: campaign_with_counts }
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
    campaign = SecurityCampaigns::SecurityCampaign.find_by(organization: org, number: campaign_number)
    deliver_error!(404, message: "Campaign not found") unless campaign

    if update_campaign!(data, campaign, org)
      campaign_with_counts = get_campaign_with_counts(campaign, org, current_user)
      deliver :organization_campaign_hash,
        { campaign: campaign, campaign_with_counts: campaign_with_counts }
    else
      deliver_error 422, errors: campaign.errors
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
    campaign = SecurityCampaigns::SecurityCampaign.find_by(organization: org, number: campaign_number)
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

  sig { params(managers: T::Array[String], org: Organization).returns(User) }
  def validate_manager!(managers:, org:)
    # We are guaranteed that there's only 1 manager by the OpenAPI spec validation
    manager_login = managers.first
    manager = User.find_by_login(manager_login)
    if manager.nil? || !SecurityCampaigns.potential_campaign_managers(org:).include?(manager)
      deliver_error! 422, errors: [
        api_error(:Campaign, :managers, :invalid, value: manager_login)
      ]
    end
    manager
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

    if repository_ids.size >= SecurityCampaigns.max_alerts_repository_count(org)
      deliver_error! 422, message: "The limit on the number of repositories was exceeded.", errors: [
        api_error(:Campaign, :code_scanning_alerts, :invalid, max_repository_ids: SecurityCampaigns.max_alerts_repository_count(org))
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

  sig { params(data: T::Hash[String, T.untyped], campaign: SecurityCampaigns::SecurityCampaign, org: Organization).returns(T.nilable(T::Boolean)) }
  def update_campaign!(data, campaign, org)
    validate_campaign_update_input!(data, campaign)

    update_params = {}
    update_params[:name] = data["name"] if data["name"]
    update_params[:description] = data["description"] if data["description"]

    if data["ends_at"]
      ends_at = validate_ends_at!(ends_at: data["ends_at"])
      update_params[:ends_at] = ends_at
    end

    if campaign.open? && data["state"] == "closed"
      update_params[:closed_at] = Time.now.utc
    elsif campaign.closed? && data["state"] == "open"
      update_params[:closed_at] = nil
    end

    if data["managers"]
      manager = validate_manager!(managers: data["managers"], org: org)
      update_params[:manager_id] = manager.id
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
    repository_ids = ActiveRecord::Base.connected_to(role: :reading) do
      resolve_repositories(repository_ids: campaign.security_campaign_alerts.distinct.pluck(:repository_id), org:).pluck(:id)
    end

    query_service = CodeScanning::AlertQueryService.for_organization(
      user: current_user,
      user_session: nil,
      organization: org,
      allowed_repository_ids: repository_ids,
    )

    SecurityCampaigns::CampaignWithCounts.load(security_campaigns: [campaign], query_service:, user: current_user).first
  end
end
