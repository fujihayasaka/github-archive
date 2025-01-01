# typed: true
# frozen_string_literal: true

# Enterprise Installation API. This is for authenticating enterprise to dotcom
class Api::EnterpriseInstallation < Api::Enterprise::App
  TTL = 5.minutes

  RANDOM_BYTES = 20

  before do
    deliver_error! 404 if GitHub.enterprise?
  end

  post "/enterprise-installation", operation_id: :internal do
    @route_owner = "@github/meao"

    # CAP can be skipped because anyone can call this endpoint
    control_access :enterprise_installation_create,
    allow_integrations: false,
    allow_user_via_granular_actor: false,
    disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    data = receive_with_schema("enterprise-installation", "create-legacy")

    log_data.update({
      github_connect_request_source: data["host_name"],
      github_connect_request_version: data["version"],
    })

    validate(data)
    token = SecureRandom.hex(RANDOM_BYTES)
    token_hash = Digest::SHA256.base64digest(token)
    # rubocop:todo GitHub/DoNotUseGlobalKv
    GitHub.kv.set("ghe-install-token-#{token_hash}", enterprise_installation_attributes(data).to_json, expires: TTL.from_now)
    # rubocop:enable GitHub/DoNotUseGlobalKv
    deliver_raw({ token: token }, status: 201)
  end

  put "/enterprise-installation", operation_id: :internal do
    @route_owner = "@github/meao"
    require_enterprise_installation!

    control_access :enterprise_installation,
      resource: current_enterprise_installation,
      allow_integrations: true,
      allow_user_via_granular_actor: false

    # The initial EAP release does not send this data, but it will be
    # required at a later point to enforce a minimal supported version.
    if request.body && request.body.size > 0
      data = receive_with_schema("enterprise-installation", "update-legacy")
      validate(data)
      current_enterprise_installation.update(enterprise_installation_attributes(data))
    end
    # The initial (OAuth-based) EAP release used this token,
    # but we switched to GitHub Apps authentication
    deliver_raw({ token: "unsupported" }, status: 200)
  end

  delete "/enterprise-installation", operation_id: :internal do
    @route_owner = "@github/meao"
    require_enterprise_installation!
    control_access :enterprise_installation,
      resource: current_enterprise_installation,
      allow_integrations: true,
      allow_user_via_granular_actor: false

    DestroyEnterpriseInstallationJob.perform_later(current_enterprise_installation)

    deliver_empty status: 202
  end

  get "/enterprise-installation/application", operation_id: :internal do
    @route_owner = "@github/meao"
    require_enterprise_installation!

    control_access :enterprise_installation,
      resource: current_enterprise_installation,
      allow_integrations: true,
      allow_user_via_granular_actor: false

    app = current_enterprise_installation.github_app

    secret = ActiveRecord::Base.connected_to(role: :writing) do
      # Cleanup all old secrets that haven't been used
      # in an hour and that the current user, namely the bot
      # has created. This ensures that the initial secret is not
      # removed as the bot didn't set that one up.
      app.client_secrets
        .except(:order)
        .where(creator_id: current_user.id)
        .where("created_at < ?", 1.hour.ago)
        .delete_all
      app.generate_client_secret(creator: current_user, bypass_secrets_limit: true)
    end

    # Value returned in milliseconds
    delay = IntegrationClientSecret.default_live_updates_wait / 1000.0
    # Do this to mask any replication delay. This flow
    # is used in the browser & API back and forth between GHES
    # and GitHub.com so we need the owner and token to be available.
    #
    # GitHub Connect setup cycles are rare so this is ok here
    # as a rare exception.
    sleep(delay)

    owner = current_enterprise_installation.owner

    payload = {
      client_id: app.key,
      client_secret: secret.secret,
      id: app.id,
      owner_type: owner.event_prefix,
      owner_identifier: owner.to_param,
      login: owner.to_param, # Backwards-compatibility for Enterprise Server < 2.17
    }

    deliver_raw(payload, status: 200)
  end

  post "/enterprise-installation/contributions", operation_id: :internal do
    @route_owner = "@github/meao"
    control_access :external_contributions,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: false,
      allow_user_via_granular_actor: true

    require_enterprise_installation!
    require_user!

    data = receive_with_schema("enterprise-contribution", "create-legacy")
    require_and_store_valid_login!(data["login"])

    created = []
    data["contributions"].each do |contrib|
      created << EnterpriseContribution.insert_or_update_contribution(current_user, current_enterprise_installation, contrib["date"], contrib["count"])
    end
    Contribution.clear_caches_for_user(current_user)
    GitHub.dogstats.increment("github_connect.contributions.reported")

    deliver_raw({ created: created.size }, status: 201)
  end

  delete "/enterprise-installation/user/contributions", operation_id: :internal do
    @route_owner = "@github/meao"
    control_access :external_contributions,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: false,
      allow_user_via_granular_actor: true

    require_enterprise_installation!
    require_user!
    EnterpriseContribution.clear_user_contributions(current_user, current_enterprise_installation)

    deliver_empty status: 204
  end

  delete "/enterprise-installation/contributions", operation_id: :internal do
    @route_owner = "@github/meao"
    require_enterprise_installation!

    control_access :enterprise_installation,
      resource: current_enterprise_installation,
      allow_integrations: true,
      allow_user_via_granular_actor: false

    EnterpriseContribution.clear_installation_contributions(current_enterprise_installation)

    deliver_empty status: 204
  end

  post "/enterprise-installation/permissions", operation_id: :internal do
    @route_owner = "@github/meao"
    require_enterprise_installation!

    control_access :enterprise_installation,
      resource: current_enterprise_installation,
      allow_integrations: true,
      allow_user_via_granular_actor: false

    data = receive_with_schema("enterprise-installation", "permissions-legacy")
    version = current_enterprise_installation.request_github_app_permissions_update(data["features"])

    if version&.errors&.any?
      deliver_error! 422, message: version.errors.full_messages.to_sentence
    end

    deliver_raw({ url: "/enterprise_installations/#{current_enterprise_installation.id}/upgrade" }, status: 201)
  end

  post "/enterprise-installation/usage-metrics", operation_id: :internal do
    @route_owner = "@github/meao"
    require_enterprise_installation!

    owner = current_enterprise_installation.owner
    otype = current_enterprise_installation.owner_type.downcase[0]

    control_access :enterprise_usage_metrics,
      resource: current_enterprise_installation,
      allow_integrations: true,
      allow_user_via_granular_actor: false

    data = receive_with_schema("enterprise-installation", "create-usage-metrics")

    GitHub.dogstats.increment("github_connect.usage_metrics.reported")

    # GHES 3.2 appliances may not send this, so we need to have a default
    # This will be fixed with a backport for 3.2 and included in 3.3 onwards.
    schema_version = data["schema_version"]
    if schema_version == "" || schema_version.nil?
      schema_version = "20210823"
    end

    event = {
      collected_at: data["collected_at"],
      server_id: data["server_id"],
      version: data["version"],
      features: data["features"],
      mec: data["mec"],
      admin_stats: data["admin_stats"],
      # We prefix the owner ID with 'u' when it's a user and 'b' when it's a business
      owner_id: "#{otype}#{owner.id}",
      dormant_users: data["dormant_users"],
      schema_version: schema_version,
      actions_stats: data["actions_stats"],
      packages_stats: data["packages_stats"],
      advisory_db_stats: data["advisory_db_stats"],
    }

    fqdn = data["host_name"]
    if !fqdn.nil? && !fqdn.empty?
      event[:host_name] = fqdn
    end

    GlobalInstrumenter.instrument("ghe_usage_metrics.event", event)
    deliver_empty status: 204
  end

  # Legacy endpoint, will go once patch is released for supported GHES versions.
  post "/enterprise-installation/usage_metrics", operation_id: :internal do
    @route_owner = "@github/meao"
    require_enterprise_installation!

    owner = current_enterprise_installation.owner
    otype = current_enterprise_installation.owner_type.downcase[0]

    control_access :enterprise_usage_metrics,
      resource: current_enterprise_installation,
      allow_integrations: true,
      allow_user_via_granular_actor: false

    data = receive_with_schema("enterprise-installation", "create-usage-metrics-legacy")

    GitHub.dogstats.increment("github_connect.usage_metrics_legacy.reported")

    # GHES 3.2 appliances may not send this, so we need to have a default
    # This will be fixed with a backport for 3.2 and included in 3.3 onwards.
    schema_version = data["schema_version"]
    if schema_version == "" || schema_version.nil?
      schema_version = "20210823"
    end

    event = {
      collected_at: data["collected_at"],
      server_id: data["server_id"],
      version: data["version"],
      features: data["features"],
      mec: data["mec"],
      admin_stats: data["admin_stats"],
      # We prefix the owner ID with 'u' when it's a user and 'b' when it's a business
      owner_id: "#{otype}#{owner.id}",
      dormant_users: data["dormant_users"],
      schema_version: schema_version,
      actions_stats: data["actions_stats"],
      packages_stats: data["packages_stats"],
      advisory_db_stats: data["advisory_db_stats"],
    }

    fqdn = data["host_name"]
    if !fqdn.nil? && !fqdn.empty?
      event[:host_name] = fqdn
    end

    GlobalInstrumenter.instrument("ghe_usage_metrics.event", event)
    deliver_empty status: 204
  end

  get "/enterprise-installation/:enterprise_or_org/server-statistics" , operation_id: "enterprise-admin/get-server-statistics" do
    enterprise_or_org = GitHub::Connect::S4.new.find_owner(params[:enterprise_or_org])
    if enterprise_or_org.nil?
      GitHub.dogstats.increment("s4.api.server_statistics.invalid_enterprise_or_org")
      deliver_error! 404
    end

    date_start = params[:date_start]
    if !date_start.nil?
      date_start = DateTime.parse(date_start).to_i
    end

    date_end = params[:date_end]
    if !date_end.nil?
      date_end = DateTime.parse(date_end).to_i
    end

    if enterprise_or_org.is_a?(Business)
      ca_key = :read_s4_enterprise_data
    elsif enterprise_or_org.is_a?(Organization)
      ca_key = :read_s4_org_data
    end

    control_access ca_key,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      resource: enterprise_or_org

    s4_client = GitHub::Connect::S4.new.client
    owner_id = enterprise_or_org.instance_of?(Business) ? "b#{enterprise_or_org.id}" : "u#{enterprise_or_org.id}"
    begin
      query_result = GitHub.dogstats.time "s4.api.server_statistics.timing" do
        s4_client.filtered_metrics(owner_id, format: "json", date_start: date_start, date_end: date_end)
      end
      GitHub.dogstats.increment("s4.api.server_statistics.reported", tags: ["status:success"])
      deliver_raw(JSON.parse(query_result), status: 200)
    rescue S4::V1::Client::ResponseError => e
      case e.code
      when :invalid_argument
        GitHub.dogstats.increment("s4.api.server_statistics.bad_requests")
        deliver_error! 422, message: "date_end must be newer than date_start"
      when :out_of_range
        GitHub.dogstats.increment("s4.api.server_statistics.bad_requests")
        deliver_error! 422, message: "date_start must be within the last 365 days"
      else
        # If we get here something in expected has gone wrong on S4
        GitHub.dogstats.increment("s4.api.server_statistics.reported", tags: ["status:error"])
        Failbot.report!(e)
        deliver_error! 500, message: "Internal server error."
      end
    end
  rescue Date::Error
    GitHub.dogstats.increment("s4.api.server_statistics.bad_requests")
    deliver_error! 422, message: "invalid date_start or date_end parameter"
  end

  class LicenseNotValid < RuntimeError
    def sub_errors
      []
    end
  end

  class HostNameNotValid < RuntimeError
    def sub_errors
      []
    end
  end

  class ServerIdNotValid < RuntimeError
    def sub_errors
      []
    end
  end

  class CollectedAtNotValid < RuntimeError
    def sub_errors
      []
    end
  end

  private

  # check if all params are present
  def validate(data)
    errors = []
    license_data = decode_data(data["license"])
    unless github_connect_authenticator.valid_license?(license_data)
      errors << LicenseNotValid.new("\"license\" is not valid")
    end
    license_hash = Digest::SHA256.base64digest(license_data)
    if ::EnterpriseInstallation.blocked?(license_hash)
      errors << LicenseNotValid.new("\"license\" is not allowed to connect to GitHub.com")
    end
    unless UrlHelper.valid_host?(data["host_name"])
      errors << HostNameNotValid.new("\"host_name\" is not valid")
    end
    unless ::EnterpriseInstallation.valid_server_id?(data["version"], data["server_id"])
      if data["server_id"].nil?
        errors << ServerIdNotValid.new("\"server_id\" must be provided for versions >= 2.17")
      else
        errors << ServerIdNotValid.new("\"server_id\" is not valid")
      end
    end

    result = ApiSchema::ValidationResult.new(errors)
    return if result.valid?
    deliver_schema_validation_error!(result)
  end

  def enterprise_installation_attributes(data)
    license_data = decode_data(data.delete("license"))
    license = github_connect_authenticator.load_license(license_data)
    {
      server_id: data["server_id"],
      license_hash: Digest::SHA256.base64digest(license_data),
      license_public_key: decode_data(license.customer_public_key),
      customer_name: license.company,
      host_name: data["host_name"],
      http_only: data["http_only"],
      public_key: data["public_key"] && decode_data(data["public_key"]),
      version: data["version"],
      features: data["features"],
      total_assigned_users: data["total_assigned_users"],
      total_dormant_users: data["total_dormant_users"],
      dormancy_threshold: data["dormancy_threshold"],
    }
  end

  def decode_data(data)
    Base64.decode64(data)
  end

  def github_connect_authenticator
    @github_connect_authenticator ||= GitHub::Connect::Authenticator.new
  end

  def require_user!
    if !logged_in?
      deliver_error! 403, message: "User is required."
    elsif !current_enterprise_installation.user_has_access?(current_user)
      deliver_error! 403, message: "User must be connected to installation."
    end
  end

  def require_and_store_valid_login!(login)
    current_enterprise_installation.set_login_for(current_user, login)
  rescue ArgumentError
    deliver_error! 422, message: "Invalid login: #{login}"
  end
end
