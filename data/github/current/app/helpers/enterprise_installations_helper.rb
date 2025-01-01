# typed: true
# frozen_string_literal: true

# Helpers for Organization/Business enterprise installations controllers
module EnterpriseInstallationsHelper
  extend T::Helpers

  requires_ancestor { ApplicationController }

  GITHUB_APP_ICON_LOCAL_PATH = "public/images/gravatars/github_connect_app-225.png".freeze

  def require_valid_installation_token
    render_404 if installations_data.nil?
  end

  def require_valid_hostname_in_data
    render_404 if !UrlHelper.valid_host?(installations_data["host_name"])
  end

  def require_valid_state
    return if params[:state] =~ /\A[a-f0-9]{16}\z/

    return_to = installation_server_return_to
    return render_404 unless return_to

    return_to.query_values = { error: "An error has occurred.  Please retry your connection." }
    redirect_to return_to.to_s
  end

  def installation_server_return_to
    Addressable::URI.parse(params[:return_to])
  rescue Addressable::URI::InvalidURIError
  end

  def require_valid_server_id_in_data
    render_404 unless ::EnterpriseInstallation.valid_server_id?(installations_data["version"], installations_data["server_id"])
  end

  def current_integration_installation
    @current_integration_installation ||= self.send(:current_installation).integration_installation
  end

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def installations_data
    @installations_data ||= raw_data && JSON.parse(raw_data)
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  def raw_data
    @raw_data ||= GitHub.kv.get("ghe-install-token-#{token_hash}").value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  def token_hash
    @token_hash ||= hashed_value(params[:token])
  end

  def hashed_value(value)
    return nil unless value.present?
    Digest::SHA256.base64digest(value)
  end

  def protocol(http_only)
    http_only ? "http" : "https"
  end

  def enterprise_installation_host_url
    # this is a hardcoded url because cloud doesn't know the enterprise account
    # slug on the server instance to formulate a full enterprise route.
    # this route will redirect to the global enterprise account on the server
    @enterprise_installation_host_url ||= "#{protocol(installations_data["http_only"])}://#{installations_data["host_name"]}/admin/dotcom_connection"
  end

  def conflicting_installations(owner, host_name)
    owner.enterprise_installations.where(host_name: host_name)
  end

  # Given an IntegrationVersion::Differ object, render the UI messages for the added/removed GitHub Connect features.
  # Returns two lists: messages for "added" features, and messages for "removed" features.
  def github_app_diff_messages(integration_diff)
    features_added = self.send(:installation).features_for_github_app_permissions(integration_diff.permissions_added)
    features_removed = self.send(:installation).features_for_github_app_permissions(integration_diff.permissions_removed)

    # Note: It's unusual to reference one controller from another.  These string lookup tables should be moved elsewhere.
    # If a feature keyword (like `license_usage_sync`) isn't in the hash, default to a string like "Foo is enabled.", instead of erroring.
    added = Businesses::DotcomConnectionController::FEATURE_ADDED_MESSAGES.fetch_values(*features_added) { |k| k.titleize + " is enabled." }
    removed = Businesses::DotcomConnectionController::FEATURE_REMOVED_MESSAGES.fetch_values(*features_removed) { |k| k.titleize + " is disabled." }

    [added, removed]
  end

  def set_github_app_icon(enterprise_installation, user)
    return if enterprise_installation.github_app.nil?

    app = enterprise_installation.github_app
    logo = IO.binread(GITHUB_APP_ICON_LOCAL_PATH)

    # App logos are avatar assets, and since GitHub uses different back-ends to
    # store avatars, the browser starts by requesting UploadPoliciesController
    # (check its header for details) a policy that tells where/how to upload.
    # Let's do the same here:
    policy_url = "#{GitHub.url}/upload/policies/avatars"
    policy_headers = { "Cookie" => request.headers["HTTP_COOKIE"] }
    policy_params = {
      "size" => logo.size,
      "content_type" => "image/png",
      "owner_type" => "Integration",
      "owner_id" => app.id,
      "authenticity_token" => authenticity_token_for(policy_url, method: :post),
    }
    policy_response = Faraday.send(:post, policy_url, policy_params, policy_headers)
    policy = JSON.parse(policy_response.body)

    # Upload logo to the URL given by the policy. This creates a new avatar.
    # (FWIW: blobs are hash-deduplicated, so we don't store multiple copies of them)
    upload_url = policy["upload_url"]
    upload_headers = policy["header"]
    upload_params = policy["form"]
    upload_params["authenticity_token"] = policy["upload_authenticity_token"] if policy["same_origin"]
    upload_params["file"] = Faraday::UploadIO.new(StringIO.new(logo), "image/png")
    upload_connection = Faraday.new do |f|
      f.request :multipart
      f.request :url_encoded
      f.adapter :net_http
    end
    upload_response = upload_connection.post(upload_url, upload_params, upload_headers)
    parsed_response_body = GitHub::JSON.parse(upload_response.body)

    # Set app primary avatar to the newly-created one
    # (like the "crop and confirm" step on the manual process).
    # Notice that the second argument is the updater, and not the user that
    # will get the avatar set (that is implicit within the avatar)
    if upload_response.success? && parsed_response_body && parsed_response_body["id"]
      avatar = Avatar.find(parsed_response_body["id"])
      PrimaryAvatar.set!(avatar, user, handle_previous_avatar: true)
    else
      error = RuntimeError.new "Avatar upload failed."
      Failbot.report error, app: "github-user"
    end
  end

  #Returns a collection of businesses that are eligible to use GitHub Connect (i.e. NOT self-service)
  def businesses_eligible_for_gh_connect(businesses)
    businesses.select { |business| business.invoiced? || GitHub.multi_tenant_enterprise? }
  end

  #Returns true if any of the businesses are eligible to use GitHub Connect (i.e. NOT self-service)
  def has_eligible_businesses_for_gh_connect?(businesses)
    businesses_eligible_for_gh_connect(businesses).any?
  end
end
