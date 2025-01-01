# typed: true
# frozen_string_literal: true

module Organization::OauthApplicationPolicyDependency
  extend T::Helpers

  requires_ancestor { Organization }

  # OauthApplications that are approved or in the process of being approved by
  # this organization.
  def oauth_applications_requesting_approval(state: nil)
    state = case state
    when :pending
      # OAuth applications that are pending approval by an organization admin.
      OauthApplicationApproval.states[:pending_approval]
    when :approved
      # OAuth applications that have been approved by an organization admin to
      # access this organization's resources.
      OauthApplicationApproval.states[:approved]
    when :denied
      # OAuth applications that an organization admin has explicitly denied
      # permission to access this organization's resources.
      OauthApplicationApproval.states[:denied]
    else
      nil
    end

    scope = self.oauth_application_approvals
    scope = scope.where(state: state) unless state.nil?

    OauthApplication.where(id: scope.pluck(:application_id)).distinct
  end

  # Public: Enables OAuth app restrictions for this org. This means tokens and
  # SSH keys created by these apps will have no access to org resources unless
  # explicitly approved by an owner.
  def enable_oauth_application_restrictions
    update_attribute :restrict_oauth_applications, true

    instrument :enable_oauth_app_restrictions
  end

  # Public: Disables the OAuth applications restrictions for this org.
  def disable_oauth_application_restrictions
    update_attribute :restrict_oauth_applications, false

    instrument :disable_oauth_app_restrictions
  end

  # Public: Does this org have an OAuth app allowlist?
  def restricts_oauth_applications?
    restrict_oauth_applications?
  end

  # Public: Request approval for an OAuth application to be able to access
  # organization resources.
  #
  # application - An OauthApplication to create an approval request for.
  # requestor   - The User requesting approval for the application.
  #
  # Returns nothing.
  def request_oauth_application_approval(application, requestor:)
    return unless can_request_application_approval?(requestor: requestor)
    return if application.third_party_oap_exempt?
    return if approval_pending_for_oauth_application?(application)
    return if allows_oauth_application?(application)
    return if approval_denied_for_oauth_application?(application)

    approval = oauth_application_approvals.create! application: application,
                                                   requestor: requestor

    instrument :oauth_app_access_requested,
      application_name: application.name,
      application_id: application.id,
      oauth_application_name: application.name

    GitHub.dogstats.increment "organization_oauth_approval", tags: ["action:requested"]

    OrganizationApplicationAccessRequestedJob.perform_later(requestor.id, approval.id)
  end

  # Public: Approve an OAuth application to be able to access this
  # organization's resources.
  #
  # application - An OauthApplication to approve.
  # approver    - The User approving the application.
  #
  # Returns the OauthApplicationApproval. (Note: this approval is returned as is
  # but maybe be modified asynchronously in a background job)
  def approve_oauth_application(application, approver:)
    return if allows_oauth_application?(application)

    approval = oauth_application_approvals.find_by(application_id: application.id)
    if approval
      approval.state = :approved
      approval.save!
    else
      approval =
        oauth_application_approvals.create! application: application,
                                            requestor: approver,
                                            state: :approved
    end

    instrument :oauth_app_access_approved,
      application_name: application.name,
      application_id: application.id,
      oauth_application_name: application.name

    GitHub.dogstats.increment "organization_oauth_approval", tags: ["action:approved"]

    OrganizationApplicationAccessApprovedJob.perform_later(approval.id, approver.id)

    approval
  end

  # Public: Deny an OAuth application access to this organization's resources.
  #
  # application - An OauthApplication to deny.
  #
  # Returns the OauthApplicationApproval. (Note: this approval is returned as is
  # but maybe be modified asynchronously in a background job)
  def deny_oauth_application(application, actor:)
    approval = oauth_application_approvals.find_by(application_id: application.id)
    return unless approval

    approval.state = :denied
    approval.save!

    RemoveRepoKeysForPolicymakerAndAppJob.perform_later(approval.organization_id, approval.application_id)

    instrument :oauth_app_access_denied,
      application_name: application.name,
      application_id: application.id,
      oauth_application_name: application.name,
      actor: actor,
      actor_id: actor.id

    GitHub.dogstats.increment "organization_oauth_approval", tags: ["action:denied"]

    approval
  end

  def block_oauth_application(application:, actor:)
    # Check if the application already has an approval record
    approval = oauth_application_approvals.find_by(application_id: application.id)

    if approval
      approval.update!(state: :blocked)
    else
      approval = oauth_application_approvals.create!(
        application: application,
        requestor: actor,
        state: :blocked
      )
    end

    instrument :oauth_app_access_blocked,
      application_name: application.name,
      application_id: application.id,
      oauth_application_name: application.name

    GitHub.dogstats.increment "organization_oauth_approval", tags: ["action:blocked"]

    approval
  end

  def unblock_oauth_application(application:, actor:)
    approval = oauth_application_approvals.find_by(application_id: application.id)
    return unless approval

    if approval.blocked? && first_party_oauth_app_restrictions_enabled?
      approval.destroy!

      instrument :oauth_app_access_unblocked,
        application_name: application.name,
        application_id: application.id,
        oauth_application_name: application.name

      GitHub.dogstats.increment "organization_oauth_approval", tags: ["action:unblocked"]
    end

    approval
  end

  # Public: Indicates if an OauthApplication is allowed to access resources
  # private to the org.
  def allows_oauth_application?(oauth_app)
    is_allowed = satisfies_oap?(oauth_app)

    if !is_allowed && GitHub.flipper[:emit_dd_oap_violation_stat].enabled?
      result = oauth_app.blockable_client_app? ? "blocked" : "unapproved"
      GitHub.dogstats.increment("org.check_allows_oauth_application", tags: ["result:#{result}"])
    end

    is_allowed
  end

  # Public: Indicates if an OauthApplication is pending approval by the org.
  def approval_pending_for_oauth_application?(oauth_app)
    return false unless restricts_oauth_applications?

    oauth_application_approvals.pending_approval.exists?(application_id: oauth_app.id)
  end

  # Public: Has the organization explicitly denied a request for the given OAuth
  # application to access the organization's resources?
  #
  # oauth_app - The OauthApplication.
  #
  # Returns a Boolean.
  def approval_denied_for_oauth_application?(oauth_app)
    return false unless restricts_oauth_applications?

    oauth_application_approvals.denied.exists?(application_id: oauth_app.id)
  end

  def can_authenticate_via_oauth?
    false
  end

  def can_authenticate_via_basic_auth?
    false
  end

  def can_authenticate_via_username_password_basic_auth?
    false
  end

  def can_request_application_approval?(requestor:)
    allows_third_party_access_requests_from_outside_collaborators? || member?(requestor)
  end

  # Public: The organization has first-party OAuth app restrictions enabled.
  #
  # Returns a Boolean.
  def first_party_oauth_app_restrictions_enabled?
    restricts_oauth_applications? && first_party_oauth_app_controls_feature_enabled?
  end

  # Public: The organization has first-party OAuth app controls feature enabled.
  #
  # The feature is enabled if the org enabled OAP and it is an EMU org.
  #
  # Returns a Boolean.
  def first_party_oauth_app_controls_feature_enabled?
    # FF enabled either for the org, or for the business that owns the org
    ff_enabled = feature_enabled?(:first_party_oauth_app_restrictions) ||
      feature_enabled?(:consider_business_oap_ff) &&
      !!(business = self.business) &&
      business.feature_enabled?(:first_party_oauth_app_restrictions)

    ff_enabled &&
    GitHub.oauth_application_policies_enabled? &&
    enterprise_managed_user_enabled?
  end

  # Private: Is the app allowed to access resources private to the org?
  def satisfies_oap?(oauth_app)
    return true unless restricts_oauth_applications?

    # first party
    return false if blocks_client_application?(oauth_app)

    # third party
    return true if oauth_app.third_party_oap_exempt?
    return true if oauth_app.owned_by?(self)

    oauth_application_approvals.
      approved.
      where(application_id: oauth_app.id).
      any?
  end

  # Private: has the client app explicitly been blocked by the org?
  def blocks_client_application?(oauth_app)
    return false unless oauth_app.blockable_client_app?
    return false unless first_party_oauth_app_restrictions_enabled?

    oauth_application_approvals.
      blocked.
      where(application_id: oauth_app.id).
      any?
  end
end
