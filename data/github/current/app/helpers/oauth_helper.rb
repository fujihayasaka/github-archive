# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module OauthHelper
  include OcticonsHelper
  include ErrorsHelper
  include ApplicationHelper
  include ApplicationLogoHelper

  extend T::Helpers

  requires_ancestor { ApplicationController } # rubocop:disable GitHub/PreventViewHelpersInControllers

  # Public: Determine if a field for setting the given OAuth app's bgcolor should be shown in the
  # page.
  #
  # Returns a Boolean.
  def allow_editing_oauth_bgcolor?(application)
    return false if application.new_record?

    if GitHub.enterprise?
      application.primary_avatar.present?
    else
      return false unless application.primary_avatar

      listing = application.marketplace_listing
      listing.nil? || !listing.publicly_listed?
    end
  end

  def oauth_app_name_options(application)
    options = {
      class: "wide",
      group_class: "mt-0",
      hint: "Something users will recognize and trust.",
      required: true,
      error: error_for(application, :name),
    }
    options[:autofocus] = "autofocus" if application.new_record?
    options
  end

  def oauth_application_logo(application, size = 80, options = {})
    oauth_application_logo_tag(application, current_user, session, size, options)
  end

  # Displays a series of spans with tool tips for the Oauth scopes.
  def scopes_description_tooltip_list(scopes)
    scope_and_description =
      if scopes.blank?
        [["public access", "Read your public profile details"]]
      else
        scopes.sort.map do |scope_name|
          scope = Api::AccessControl.scopes[scope_name]
          description = scope ? scope.description.capitalize : "Unknown scope"
          [scope_name, description]
        end
      end

    scope_spans = scope_and_description.map do |title, description|
      content_tag(:span, title,
        title: description)
    end

    content_tag(:em, h("— ") + safe_join(scope_spans, ", "))
  end

  # Displays an unordered list of human OAuth scope descriptions.
  def scopes_description_list(scopes)
    check = octicon("check", class: "color-fg-success mr-1")
    inner = safe_join(
      descriptions_for_scopes(scopes).map do |description|
        content_tag(:div, safe_join([check, description], " "), class: "pl-0 listgroup-item")
      end,
      "\n",
    )

    content_tag(:div, inner)
  end

  # Public: Builds a simple english sentence for describing this set of scopes.
  #
  # scopes - The set of scopes to return english descriptions for.
  #
  # Returns an Array of String sentence fragments.
  def descriptions_for_scopes(scopes)
    if scopes.blank?
      ["Access public information (read-only)"]
    else
      scopes.sort.each.map do |s|
        next unless scope = Api::AccessControl.scopes[s]
        scope.description.capitalize
      end.compact
    end
  end

  def user_integration_permissions(access)
    keys = User::Resources.subject_types & access.authorization.integration_version.default_permissions.keys
    permissions = keys.map do |key|
      key.to_s + ":" + access.authorization.integration_version.default_permissions[key].to_s
    end
    permissions.any? ? permissions : "none"
  end

  # Determine whether the given scopes would allow privileged access to org
  # (i.e., do they provide at least viewing private organization-owned resources
  # or mutating public organization-owned resources?).
  #
  # scopes - Array of String scope names.
  #
  # Returns a Boolean.
  def scopes_include_privileged_org_access?(scopes)
    return false if scopes.blank?

    (scopes - Api::AccessControl::SCOPES_WITHOUT_PRIVILEGED_ORGANIZATION_ACCESS).any?
  end

  # Determine whether to prompt the user to request organization approval for
  # an application.
  #
  # user        - A User.
  # application - An OauthApplication.
  # scopes      - An Array of String scope names defining the application's
  #               level of access for the user.
  #
  # Returns a Boolean.
  def request_organization_approval?(user:, application:, scopes:)
    return false unless GitHub.oauth_application_policies_enabled?

    user.authorizable_organizations.any? &&
      scopes_include_privileged_org_access?(scopes) &&
      !application.oap_exempt?
  end

  def last_authorization_access_description(authorization)
    cutoff = OauthAuthorization::ACCESS_CUTOFF_DATE
    key = if authorization.accessed_at ||
             (authorization.created_at && authorization.created_at > cutoff)
      authorization
    else
      # For old data we have no other option but to look through the collection
      # of accesses and public keys that the authorization is tracking and try
      # to derive a best guess at the last access. This is not 100% accurate
      # since a given access or public key that was recently used may have
      # been deleted, and hence we would not know about it.
      most_recently_created_access =
        authorization.accesses.max_by { |x| x.created_at.to_i }
      most_recently_accessed_access =
        authorization.accesses.max_by { |x| x.accessed_at.to_i }

      most_recently_created_public_key =
        authorization.public_keys.max_by { |x| x.created_at.to_i }
      most_recently_accessed_public_key =
        authorization.public_keys.max_by { |x| x.accessed_at.to_i }

      most_recently_accessed = [
        most_recently_accessed_access,
        most_recently_accessed_public_key,
      ].compact.max_by { |x| x.accessed_at.to_i }

      most_recently_created = [
        most_recently_created_access,
        most_recently_created_public_key,
      ].compact.max_by { |x| x.created_at.to_i }

      if most_recently_accessed && most_recently_accessed.accessed_at
        most_recently_accessed
      else
        most_recently_created
      end
    end

    last_access_description(key, "Oauth authorization")
  end

  # Public: Returns the integration object if the client_id matches the integration key pattern
  # otherwise, it will return an oauth application
  #
  # client_id - A key associated to an Integration or OauthApplication obj
  #
  # Returns an associated object from the client_id
  def get_application(client_id)
    return unless client_id.is_a? String

    app = OauthAccess::ClientId.application(key: client_id)
    owner = if app
      owner_id = app.is_a?(OauthApplication) ? app.user_id : app.owner_id
      User.unscoped.find_by(id: owner_id)
    end

    if app && app.class.client_id_type(client_id) == :v2 && !owner&.feature_enabled?(:globally_unique_client_ids)
      nil
    else
      app
    end
  end

  # Public: Sets and returns the list of permitted query params for the account picker flow.
  def account_picker_params
    blocked_params = request.path_parameters.keys
    blocked_params.append :authenticity_token # block authenticity token to prevent CSRF bypass
    params.except(*blocked_params).permit!
  end

end
