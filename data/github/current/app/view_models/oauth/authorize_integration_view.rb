# typed: true
# frozen_string_literal: true

class Oauth::AuthorizeIntegrationView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include ApplicationHelper # provides `coarse_time_ago_in_words`
  include GitHub::Memoizer

  attr_reader :application, :approval, :authorization, :previous_version, :params, :redirect_uri,
    :rate_limited, :session, :form_submission_path, :include_device_warning, :device_authorization,
    :redirect_uri_specified
  attr_accessor :show_deleted

  delegate :key, :name, :owner, :preferred_bgcolor, to: :application
  delegate :user,                                   to: :authorization

  OCTICON_FOR_PERMISSION = {
    "blocking"                => "blocked",
    "codespaces_user_secrets" => "codespaces",
    "copilot_messages"        => "copilot",
    "copilot_editor_context"  => "copilot",
    "emails"                  => "mail",
    "user_events"             => "calendar",
    "external_contributions"  => "zap",
    "followers"               => "thumbsup",
    "interaction_limits"      => "no-entry",
    "gists"                   => "logo-gist",
    "git_signing_ssh_public_keys" => "verified",
    "gpg_keys"                => "verified",
    "keys"                    => "key",
    "starring"                => "star",
    "watching"                => "eye",
    "plan"                    => "briefcase",
    "profile"                 => "person",
    "knowledge_bases"         => "book",
  }

  DESCRIPTION_SUFFIX = {
    "blocking"  => "users blocked by you",
    "emails"    => "your email addresses",
    "followers" => "users you follow",
    "git_signing_ssh_public_keys" => "your SSH signing public keys",
    "gpg_keys" => "your public GPG keys",
    "interaction_limits" => "your interaction limits",
    "keys"      => "your Git SSH keys",
    "starring"  => "your starred repositories",
    "watching"  => "your watched repositories",
    "plan"      => "your subscription plan on GitHub",
    "knowledge_bases" => "knowledge bases you have access to",
  }

  # Array of relevant oauth params
  OAUTH_KEYS = [:client_id, :redirect_uri, :type, :state, :user_code]

  MAX_INSTALLATION_ACCOUNT_NAMES = 5

  def description(resource)
    unless DESCRIPTION_SUFFIX.key?(resource)
      return Permissions::FineGrainedResources::Metadata.description(resource)
    end

    prefix = permissions[resource] == :write ? "View and manage" : "View"
    prefix + " " + DESCRIPTION_SUFFIX[resource]
  end

  def human_name(resource)
    Permissions::FineGrainedResources::Metadata.title(resource)
  end

  def permission_text(permission)
    Permissions::FineGrainedResources::Metadata.action_description(permission)
  end

  # Public: Hash of oauth params to submit with authorization request.
  #
  # Returns a Hash.
  def oauth_params
    initial = {}
    initial[:redirect_uri_specified] = true if redirect_uri_specified

    OAUTH_KEYS.each_with_object(initial) do |key, hash|
      next if params[key].nil?
      hash[key] = params[key]
    end
  end

  def permissions
    return @permissions if defined?(@permissions)
    @permissions = (integration_version || @application.latest_version).user_permissions
  end

  def latest_app_permissions
    return @latest_permissions if defined?(@latest_permissions)
    @latest_permissions = @application.latest_version.user_permissions
  end

  def integration_version
    return @integration_version if defined?(@integration_version)

    @integration_version = nil
    return unless existing_integration_version?

    @integration_version = IntegrationVersion.includes(:default_permission_records).find_by(
      integration: @application,
      number: @authorization.integration_version_number
    )
  end

  def octicon_for_permission(permission)
    OCTICON_FOR_PERMISSION.fetch(permission, "file")
  end

  # Public: Boolean if this application already has access.
  #
  # Returns truthy if the application already has access to this user.
  def existing_authorization?
    @authorization.present?
  end

  # Public: Boolean if this authorization has an IntegrationVersion set.
  #
  # Returns a Boolean.
  def existing_integration_version?
    @authorization.try(:integration_version_number).present?
  end

  # Public: Boolean if this authorization has an IntegrationVersion for a previous
  # version to diff against
  #
  # Returns a Boolean.
  def existing_previous_version?
    @previous_version.present?
  end

  # Public: Boolean if the application type is of type `Integration`.
  #
  # Returns true if there is an OauthAuthorization's application
  # is of type `Integration`.
  def integration_application_type?
    return false unless existing_authorization?
    @authorization.integration_application_type?
  end

  # Public: Should OAuth access be blocked for this user because of mandatory
  # email verification?
  #
  # Returns a Boolean.
  def block_for_mandatory_email_verification?
    @block_for_mandatory_email_verification ||= begin
      GitHub.dogstats.increment "oauth.email_verification", tags: ["action:checked", "type:#{current_user.signup_timeframe}"]
      if current_user.must_verify_email?
        OauthAccessTokens::Domain.instrument_email_verification_required(user: current_user, application_id: application.id)
        return true
      end
      false
    end
  end

  # Public: Determine whether to show the Reauthorization button.
  #
  # Returns a Boolean.
  def rate_limited?
    existing_authorization? && !!@rate_limited
  end

  def application_creation_time_in_words
    if application.created_at > 1.day.ago
      "less than a day"
    else
      coarse_time_ago_in_words(application.created_at)
    end
  end

  memoize def application_user_count
    user_ids = application.authorizations.limit(2000).pluck(:user_id)
    User.not_spammy.where(id: user_ids).limit(1001).count
  end

  def application_user_range
    case application_user_count
    when 0...10
      "Fewer than 10"
    when 10...100
      "Fewer than 100"
    when 100...1000
      "Fewer than 1K"
    else
      "More than 1K"
    end
  end

  def application_redirect_origin
    Addressable::URI.parse(redirect_uri).origin
  end

  def application_owner
    return @application_owner if defined?(@application_owner)
    @application_owner = @application.github_owned? ? "GitHub" : owner.safe_profile_name
  end

  def owner_display_login
    application_owner
  end

  def application_github_owned?
    application.github_owned?
  end

  def installed_account_names
    return @installed_account_names if defined?(@installed_account_names)

    target_user_ids = installations_with_current_user.pluck(:target_id)
    @installed_account_names = User.where(id: target_user_ids).order(login: :asc).limit(MAX_INSTALLATION_ACCOUNT_NAMES).pluck(:display_login)
  end

  def application_owner_path
    case owner
    when Business
      urls.enterprise_path(owner)
    else
      urls.user_path(owner)
    end
  end

  def existing_installations_message
    builder = []

    GitHub.dogstats.distribution_time("authorize_integration.existing_installations_message") do
      if installations_with_current_user.exists?
        builder << "#{application.name} has been installed on "
        builder << helpers.pluralize(installations_with_current_user.count, "account")
        builder << " you have access to: "

        # In the event we have capped the number listed accounts,
        # we add "more" on the end of the array so that we can
        # have "and more."
        #
        # Example:
        #
        #   >> MAX_INSTALLATION_ACCOUNT_NAMES
        #   => 2
        #   >> installations_with_current_user.count
        #   => 3
        #   >> installation_account_names
        #   => ["cli", "desktop"]
        #   >> existing_installations_message
        #   => "Dummy Application has been installed on 3 accounts you have access to: cli, desktop, and more."

        account_names = installed_account_names
        account_names << "more" if installations_with_current_user.count > installed_account_names.count

        builder << helpers.content_tag(:strong, installed_account_names.to_sentence) # rubocop:disable Rails/ViewModelHTML
        builder << "."
      else
        builder << "#{application.name} has not been installed on any accounts you have access to."
      end
    end

    helpers.safe_join(builder)
  end

  def diff
    return @_diff if defined?(@_diff)
    @_diff = if existing_previous_version?
      integration_version.diff(previous_version)
    else
      @application.latest_version.diff(integration_version)
    end
  end

  def permissions_added
    filter_user_permissions(diff.permissions_added)
  end

  def permissions_upgraded
    filter_user_permissions(diff.permissions_upgraded)
  end

  def permissions_downgraded
    filter_user_permissions(diff.permissions_downgraded)
  end

  def permissions_removed
    filter_user_permissions(diff.permissions_removed)
  end

  def permissions_unchanged
    filter_user_permissions(diff.permissions_unchanged)
  end

  def filter_user_permissions(permissions)
    permissions.select { |resource, _action| User::Resources.subject_types.include?(resource) }
  end

  def device_authorization?
    oauth_params.key?(:user_code) && !oauth_params.key?(:redirect_uri)
  end

  def include_device_warning?
    !!@include_device_warning
  end

  def ip_address
    return @ip_address if defined?(@ip_address)
    @ip_address = @device_authorization.try(:ip)
  end

  def location
    return @location if defined?(@location)
    @location = @device_authorization.try(:location)
  end

  def location_available?
    ip_address.present? || location.present?
  end

  def device_code_created_at
    @device_authorization.created_at.to_formatted_s(:deprecation_mailer)
  end

  private

  def installations_with_current_user
    return @installations_with_current_user if defined?(@installations_with_current_user)
    @installations_with_current_user = @application.installations.with_user(current_user)
  end
end
