# typed: true
# frozen_string_literal: true

class Api::OrganizationSecretScanning < Api::App
  include Api::App::SecretScanningHelpers
  include ReceiveSchemaWithOpenApi

  # GA Secret Scanning APIs
  # get a list of secret scanning alerts for an organization
  get "/organizations/:organization_id/secret-scanning/alerts", operation_id: "secret-scanning/list-alerts-for-org" do
    # Ensure the org is capable of having secret scanning alerts
    deliver_error!(404) unless SecretScanning::Features::Org::TokenScanning.new(org).feature_available?

    control_access :list_org_secret_scanning_alerts,
      resource: org,
      organization: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if access_allowed?(:list_org_secret_scanning_alerts_for_only_public_repos, resource: org, allow_integrations: false, allow_user_via_granular_actor: false)
      GitHub.dogstats.increment("secret_scanning.api.org_alerts.public_repo_PAT_scope")
    end

    # Filter by state, if provided in the query
    state = nil
    if params[:state]
      state = params[:state].downcase.to_sym
      if state != :open && state != :resolved
        deliver_error!(400, message: "State needs to be either 'open' or 'resolved'")
      end
    end

    # Filter by resolution, if provided in the query
    resolutions = []
    if params[:resolution]
      params[:resolution].split(",").each do |resolution|
        service_enum = get_service_enum_from_alert_resolution(resolution)
        if service_enum.nil?
          deliver_error!(422, message: "resolution is invalid: it must be one of 'revoked', 'false_positive', 'used_in_tests', 'pattern_deleted', 'pattern_edited', 'hidden_by_config' or 'wont_fix'")
        end
        resolutions << service_enum
      end
    end

    # Filter by validity, if provided in the query
    validity_service_params = get_service_enums_from_validity_param(params[:validity])
    unless validity_service_params[:error].nil?
      deliver_error!(422, message: validity_service_params[:error])
    end
    validities = validity_service_params[:validities]

    slug_types = nil
    if params[:secret_type]
      slug_types = params[:secret_type].split(",")
    end

    # If this is a request where the actor has programmatic granular permissions, filter the repositories before we send the request to Token Scanning Service.
    repo_ids = nil
    if access_allowed?(
      :list_org_secret_scanning_alerts_for_programmatic_actor_installed_on_some_repos,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    )
      repo_ids = ProgrammaticActor::Grant
        .with(current_user)
        .with_target(org)
        .repository_ids(min_action: :read, resource: "secret_scanning_alerts")

      # Bail out early if the programmatic actor doesn't have access to any repositories.
      deliver_error!(404) if repo_ids.empty?
    end

    GitHub.dogstats.distribution("secret_scanning.api.page", pagination[:page], tags: ["scope:organization"])

    is_publicly_leaked = false
    is_multi_repo = false
    if feature_flag_enabled_in_hierarchy?(org, FeatureFlags::SHOW_SINGLE_ALERT_VIEW_RELATED_ALERTS) || (org.business && feature_flag_enabled_in_hierarchy?(org.business, FeatureFlags::SHOW_SINGLE_ALERT_VIEW_RELATED_ALERTS))
      is_publicly_leaked = params[:is_publicly_leaked] == "true"
      is_multi_repo = params[:is_multi_repo] == "true"
    end

    results = get_alerts_for_org(
      org,
      state,
      slug_types,
      params[:sort],
      params[:direction],
      per_page,
      params[:page],
      params[:before],
      params[:after],
      repo_ids,
      resolutions,
      repo_visibilities,
      validities,
      is_publicly_leaked,
      is_multi_repo,
      feature_flag_enabled_in_hierarchy?(org, FeatureFlags::DISPLAY_HAS_MORE_LOCATIONS),
    )

    hide_secret = false
    if params[:hide_secret].present?
      hide_secret = params[:hide_secret] == "true"
    end

    unless hide_secret
      # If encrypted secrets were retrieved, we may be able to decrypt them here
      results[:alerts].each { |alert| set_raw_secret_from_encrypted_secret(alert) }

      alerts_without_raw_secrets = results[:alerts].select { |alert| alert.raw_secret.blank? }
      alerts_without_raw_secrets.each { |alert| SecretScanning::Util::RawSecret.replacement_for_nil_raw_secret(alert) }
    end

    total_count = results[:total]
    if state == :open
      total_count = results[:unresolved_count]
    elsif state == :resolved
      total_count = results[:resolved_count]
    end

    setup_cursor_paging_links(results) if params[:before] || params[:after]
    deliver :org_secret_scanning_alerts_hash, { alerts: results[:alerts], total_count: total_count }
  end

  private

  def org
    return @_org if defined?(@_org)
    @_org = find_org!
  end

  def repo_visibilities
    @_repo_visibilities ||= begin
      if access_allowed?(:list_org_secret_scanning_alerts_for_only_public_repos, resource: org, allow_integrations: false, allow_user_via_granular_actor: false)
        [Repository::PUBLIC_VISIBILITY]
      else
        Repository::VISIBILITIES
      end
    end
  end
end
