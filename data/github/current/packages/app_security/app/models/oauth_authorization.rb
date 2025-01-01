# typed: true
# frozen_string_literal: true

require "oauth_util"

class OauthAuthorization < ApplicationRecord::Domain::Integrations

  include GitHub::Relay::GlobalIdentification
  include Ability::Actor
  include GitHub::FlipperActor
  include GitHub::VexiActor
  include GitHub::Validations
  include Instrumentation::Model

  # Any authorization created after this date is "new" and we can fully
  # determine whether a given authorization has been used or not. Before this
  # date we can't say for certain.
  ACCESS_CUTOFF_DATE = Time.utc(2015, 12, 16)

  OAUTH_APPLICATION = "OauthApplication"
  INTEGRATION = "Integration"

  # Public: The User record that granted this access.
  belongs_to :user
  validates_presence_of :user_id
  validate :owner_is_human

  # Public: The OauthApplication or Integration that has been authorized.
  belongs_to :application, polymorphic: true

  # rubocop:todo Rails/InverseOf
  belongs_to :oauth_application, -> { where("oauth_authorizations.application_type = ?", "#{OAUTH_APPLICATION}") },
    foreign_key: "application_id"
  # rubocop:enable Rails/InverseOf

  # rubocop:todo Rails/InverseOf
  belongs_to :integration, -> { where("oauth_authorizations.application_type = ?", INTEGRATION) },
    foreign_key: "application_id"
  # rubocop:enable Rails/InverseOf

  validates_presence_of :application_id
  validates_presence_of :application_type

  # Public: String description of this authorization (used for personal access
  # tokens) column :description
  validates_presence_of :description, if: :personal_access_authorization?
  validates :description, unicode3: true

  # Public: PublicKeys associated with this authorization.
  has_many :public_keys
  destroy_dependents_in_background :public_keys

  # Public: OauthAccesses associated with this authorization.
  # rubocop:todo Rails/InverseOf
  has_many :accesses, class_name: "OauthAccess", foreign_key: :authorization_id, dependent: :destroy
  # rubocop:enable Rails/InverseOf

  serialize :scopes, coder: JSON

  validate :scopes_are_allowed

  after_create_commit  :instrument_creation
  after_update_commit :instrument_update
  before_destroy :generate_integration_webhook_payload
  # `prepend: true` to ensure that this runs before any `dependent: destroy` hooks
  # see https://api.rubyonrails.org/classes/ActiveRecord/Callbacks.html#module-ActiveRecord::Callbacks-label-Ordering+callbacks
  before_destroy :clear_mobile_auth_keys, if: :github_mobile_oauth_app?, prepend: true
  after_destroy_commit :clear_permissions, if: :integration_application_type?
  after_destroy_commit :clear_mobile_device_tokens, if: :github_mobile_oauth_app?
  after_destroy_commit :instrument_deletion

  after_commit :notify_owner_of_github_app_with_new_user_permissions,      on: :create
  after_commit :notify_owner_of_github_app_with_upgraded_user_permissions, on: :update
  after_commit :notify_owner_of_private_data_scopes_created, on: :create
  after_commit :notify_owner_of_private_data_scopes_updated, on: :update

  scope :for_client_id, -> (client_id) {
    if Integration.client_id?(client_id)
      joins(:integration).where("oauth_applications.key = ?", client_id)
    else
      joins(:oauth_application).where("oauth_applications.key = ?", client_id)
    end
  }

  # Access tokens associated with the generic personal token application id.
  scope :personal_tokens, -> { where(application_id: OauthApplication::PERSONAL_TOKENS_APPLICATION_ID) }

  scope :since, -> (time) { where("oauth_authorizations.created_at >= ?", time) }

  # OAuth authorizations for oauth apps that are true third-party
  # applications (excludes personal tokens and GitHub owned applications).
  scope :third_party, -> {
    joins(:oauth_application) \
    .where(
      "`application_id` != ? AND `oauth_applications`.`user_id` != ?",
      OauthApplication::PERSONAL_TOKENS_APPLICATION_ID,
      GitHub.trusted_apps_owner_id
    )
  }

  # OAuth authorizations for github apps that are true third-party
  # applications (excludes personal tokens and GitHub owned applications).
  scope :third_party_github_apps, -> {
    joins(:integration) \
    .github_apps \
    .where("`integrations`.`owner_id` != ?", GitHub.trusted_apps_owner_id)
  }

  scope :github_apps, -> { where("`application_type` = ?", INTEGRATION) }
  scope :oauth_apps, -> { where("`application_id` != ? AND `application_type` =?",
    OauthApplication::PERSONAL_TOKENS_APPLICATION_ID, "#{OAUTH_APPLICATION}")
  }

  # Excludes oauth_authorizations belonging to apps that cannot be revoked by
  # a user.
  #
  # app_type:   Class, one of either OauthApplication or Integration
  scope :user_revocable, ->(app_type, internal_apps_query = Apps::Privileged::Query.new) {
    return all unless [Integration, OauthApplication].include?(app_type)

    irrevocable = internal_apps_query.with_capability(:can_auto_approve_oauth_authorization, type: app_type)
    return all if irrevocable.empty?

    case app_type.name
    when "OauthApplication"
      oauth_apps.where.not(application_id: irrevocable)
    when "Integration"
      github_apps.where.not(application_id: irrevocable)
    end
  }

  def integration_application_type?
    application_type == INTEGRATION
  end

  def github_mobile_oauth_app?
    return false unless application_type == OAUTH_APPLICATION

    android_app_id = Apps::Privileged.oauth_application(:android_mobile)&.id
    ios_app_id = Apps::Privileged.oauth_application(:ios_mobile)&.id

    [android_app_id, ios_app_id].compact.include?(application_id)
  end

  # OAuth authorizations for applications that are managed by the GitHub
  # organization (excludes personal tokens).
  scope :github_owned, -> {
    joins(:oauth_application)
      .order("oauth_applications.name ASC")
      .where(
        "`application_id` != ? AND `oauth_applications`.`user_id` = ?",
        OauthApplication::PERSONAL_TOKENS_APPLICATION_ID,
        GitHub.trusted_apps_owner_id,
      )
  }

  def add_scopes(new_scopes)
    return unless new_scopes

    new_scopes = OauthAccessTokens::Domain.normalize_scopes(
      Array(scopes) | new_scopes,
      visibility: :all,
    )

    self.scopes = new_scopes
  end

  def add_scopes!(new_scopes)
    add_scopes(new_scopes)
    save!
  end

  def unused?
    accesses.empty? && public_keys.empty?
  end

  # Gets the attached OauthApplication, or a default OauthApplication for
  # OauthAccess records created through the API.
  #
  # Returns an OauthApplication.
  def safe_app
    if personal_access_authorization?
      @safe_app ||= OauthApplication.default(description)
    else
      application || (@safe_app ||= OauthApplication.default("MISSING_APP"))
    end
  end

  # Window of time between accessed_at DB writes.
  #
  # Returns a duration.
  ACCESS_THROTTLING = 1.week

  # Public: Register this oauth authorization has been used
  #
  # This only updates the timestamp within an interval to prevent a lot
  # of writes if used often in a short period of time.
  #
  # Returns nothing
  def bump(time = Time.now)
    return if bumped_within_throttling_period?(time)

    if GitHub.cache.add(last_accessed_memcache_key, time, ACCESS_THROTTLING.to_i)
      OauthAuthorizationBumpJob.perform_later(T.must(id), time.to_i)
    end
  end

  def bump!(time)
    return if bumped_within_throttling_period?

    ActiveRecord::Base.connected_to(role: :writing) do
      threshold = ACCESS_THROTTLING.ago.to_formatted_s(:db)
      self.class.connection.update(Arel.sql(<<-SQL, id: id, accessed_at: time, threshold: threshold))
        UPDATE oauth_authorizations SET accessed_at = :accessed_at
        WHERE id = :id AND (accessed_at < :threshold OR accessed_at IS NULL)
      SQL
    end

    nil
  end

  # Public: Has this authorization been bumped in the access throttling period.
  #
  # now - The time to use to determine the end of the throttling period.
  #
  # Returns true if bumped within period else false.
  def bumped_within_throttling_period?(now = Time.now)
    return false if accessed_at.blank?
    T.must(accessed_at) > (now - ACCESS_THROTTLING)
  end

  # Public: Indicates whether this is a personal access authorization.
  #
  # Returns a Boolean.
  def personal_access_authorization?
    application_id == OauthApplication::PERSONAL_TOKENS_APPLICATION_ID
  end

  def oauth_application_authorization?
    application_type == OAUTH_APPLICATION && !personal_access_authorization?
  end

  # Can the Oauth App be a granted an Ability or UserRole over a given subject?
  # An Oauth App can only be granted a subset of the permissions that the owner user is allowed to perform over the subject.
  # So there is no need for additional guards when granting permissions.
  def can_be_granted_permission_over!(subject, action); end

  # Public: Destroy access and instrument the deletion using the provided
  # explanation
  #
  # payload - Symbol of the explanation for deletion. All valid Symbols can be
  # found in OauthUtil::VALID_DESTROY_EXPLANATIONS. These symbols are mapped
  # to a more descriptive explanation that will be shown in the audit log.
  #
  # Returns the result of calling destroy() on the model instance.
  def destroy_with_explanation(explanation, entry_point:)
    unless OauthUtil.destroy_explanation(explanation)
      raise ArgumentError, "invalid destroy explanation: #{explanation}"
    end
    @destroy_explanation = explanation
    destroy_with_args(entry_point: entry_point)
  end

  # Public: Returns a boolean that determines if the given set of scopes are
  # safely less permissive than this authorization's scopes. Less permissive
  # means the scopes are equal to or less permissive than the current grant OR
  # the other scope request is blank (which has a specicial meaning in the oauth
  # flow to preserve the existing scopes).
  #
  # requested_scopes - An Array of String scopes or a String of comma-separate scopes
  #
  # Returns a truthy if the other scopes are equal or less permissive than the
  # current authorization.
  def safely_less_permissive?(requested_scopes)
    return true if requested_scopes.blank?

    requested_scopes = OauthAccessTokens::Domain.normalize_scopes(requested_scopes, visibility: :all)
    current_scopes   = OauthAccessTokens::Domain.normalize_scopes(scopes, visibility: :all)

    # Are the newly requested scopes a subset of the existing scopes?
    return true if (delta = requested_scopes - current_scopes).blank?

    # Check if all newly requested scopes are covered by an existing scope.
    delta.all? { |s| Api::AccessControl.scopes[s].has_scopes?(current_scopes) }
  end

  # Public: Determine if the latest IntegrationVersion
  # for the application can be upgraded to without the User needing to consent.
  #
  # The cases for upgrading without consent are:
  # - Existing user permissions are unchanged
  # - Existing user permissions are downgraded (:write -> :read)
  # - Existing permissions are removed
  #
  # Returns a Boolean.
  def upgradedable_without_user_permission?
    return false unless integration_version.present?
    return true unless outdated?

    diff = application.latest_version.diff(integration_version)

    return false if diff.permissions_added.keys.any?    { |permission| User::Resources.subject_types.include?(permission) }
    return false if diff.permissions_upgraded.keys.any? { |permission| User::Resources.subject_types.include?(permission) }

    true
  end

  def outdated?
    return false unless integration_application_type?
    return false if integration_version_number.nil?

    T.must(integration_version_number) < application.latest_version.number
  end

  def can_have_granular_user_permissions?
    integration_application_type?
  end

  def integration_version
    return nil unless integration_application_type?
    application.versions.find_by(number: integration_version_number)
  end

  # Public: Notifies the owner that the token associated with their OAuthAuthorization
  # has been regenerated. We make this method public since the token regeneration
  # occurs in the oauth_access for a personal access token however the scopes are
  # associated with the authorization
  def notify_owner_of_token_regeneration
    notify_owner_of_private_data_scopes(is_new_record: false, is_regenerated: true)
  end

  def platform_type_name
    if personal_access_authorization?
      "PersonalAccessToken"
    elsif integration_application_type?
      "GitHubAppAuthorization"
    else
      "ThirdPartyOauthAuthorization"
    end
  end

  def abilities(subject_types: [], subject_ids: [])
    params = {
      actor_id: ability_id,
      actor_type: ability_type,
      priority: Ability.priorities[:direct],
    }
    params[:subject_type] = subject_types if subject_types.any?
    params[:subject_id] = subject_ids if subject_ids.any?
    Permission.where(params)
  end

  # Public: Destroys the OAuth authorization and propagates kwargs to AR callback methods
  #
  # callback_args - keyword arguments to propagate to AR callback methods
  def destroy_with_args(**callback_args)
    @callback_args = callback_args
    self.destroy
  end

  private

  # The user who performed the action as set in the GitHub request context. If the context doesn't
  # contain an actor, fallback to the user that the oauth authorization belongs to.
  def event_actor
    return @event_actor if defined?(@event_actor)
    @event_actor = (User.find_by(id: GitHub.context[:actor_id]) || user)
  end

  def last_accessed_memcache_key
    "oauth_authorizations:last_accessed:#{id}"
  end

  def scopes_are_allowed
    bad_scopes = OauthAccessTokens::Domain.invalid_scopes(scopes)
    return if bad_scopes.blank?
    errors.add :scopes, "are invalid: #{bad_scopes.to_sentence}"
  end

  def owner_is_human
    return if user.blank?

    errors.add :user_id, "must be a human" unless T.must(user).user?
  end

  def event_prefix() :oauth_authorization end

  def scopes_string
    Array(scopes).map { |scope| scope.to_s }.sort.join(",")
  end

  def event_payload
    org_id = if user
      if personal_access_authorization?
        # A PAT can access all orgs a user can access.
        T.must(user).organization_ids
      elsif safe_app.third_party_restrictions_applicable?
        # Only log the organizations that an authorization can actually access.
        T.must(user).organizations.oauth_app_policy_met_by(safe_app).pluck(:id)
      end
    end

    {
      oauth_authorization_id: id,
      application_id: application_id,
      application_type: application_type,
      application_name: safe_app.name,
      scopes: scopes,
      token_scopes: scopes_string,
    }.tap do |payload|
      if user.present?
        the_user = T.must(user)
        payload[the_user.event_prefix] = user
        orgs =
          if personal_access_authorization?
            # A PAT can access all orgs a user can access.
            the_user.organizations
          elsif safe_app.third_party_restrictions_applicable?
            # Only log the organizations that an authorization can actually access.
            the_user.organizations.oauth_app_policy_met_by(safe_app)
          end
      end

      if orgs&.any?
        payload[:org_id] = orgs.pluck(:id)
        payload[:org] = orgs.pluck(:display_login)
      end

      if oauth_application_authorization?
        payload[:oauth_application_name] = safe_app.name
      end

      if integration_application_type?
        payload[:integration] = safe_app.name
      end
    end
  end

  def instrument_creation(payload = {})
    GlobalInstrumenter.instrument("oauth_authorization.create", { oauth_authorization: self })

    instrument :create, payload
  end

  def instrument_update(payload = {})
    if saved_change_to_scopes?
      instrument :update, payload
    end
  end

  def instrument_deletion(payload = {})
    if event_actor&.employee? && event_actor != user
      actor_hash = GitHub.guarded_audit_log_staff_actor_entry(event_actor)
      payload = payload.merge(actor_hash)
    end

    instrument :destroy, payload.merge(explanation: @destroy_explanation)
    queue_integration_webhook_delivery

    explanation_key = @destroy_explanation || "none"
    GitHub.dogstats.increment("account_security.oauth_authorization", tags: ["explanation:#{explanation_key.to_s.gsub(/_/, "-")}", "action:destroy"])
  end

  def clear_permissions
    entry_point = (defined?(@callback_args) && @callback_args[:entry_point]) || :unknown_oauth_authorization_clear_permissions
    Permissions::QueryRouter.delete_app_permissions_on_actor(self, entry_point: entry_point)
  end

  def clear_mobile_device_tokens
    Notifyd::DeviceTokensService.delete_all(user_id:)
  end

  def clear_mobile_auth_keys
    return unless user && accesses.any?
    DestroyMobileAuthDeviceKeysJob.perform_later(user, id, application, accesses.pluck(:id))
  end

  def generate_integration_webhook_payload
    return unless integration_application_type?

    event = Hook::Event::GitHubAppAuthorizationEvent.new(
      action:         :revoked,
      actor_id:       user_id,
      triggered_at:   Time.now,
      integration_id: application_id,
    )

    @delivery_system = Hook::DeliverySystem.new(event)
    @delivery_system.generate_hookshot_payloads
  end

  # Private: Queue the payloads generated above for delivery to Hookshot.
  def queue_integration_webhook_delivery
    return unless defined?(@delivery_system)
    @delivery_system.deliver_later
  end

  def notify_owner_of_private_data_scopes_created
    notify_owner_of_private_data_scopes(is_new_record: true, is_regenerated: false)
  end

  def notify_owner_of_private_data_scopes_updated
    notify_owner_of_private_data_scopes(is_new_record: false, is_regenerated: false)
  end

  PUBLIC_DATA_SCOPES = Set.new(%w(read:user))

  # Private: sends notification email to owner of token. This is used as a signal
  # and warning of account compromise. Scopeless / public data scopes are
  # excluded so new scopes are automatically included.
  #
  # Scopeless tokens never generate alert, otherwise:
  #   PATs always generate alerts
  #   Applications generate alerts unless:
  #     read:user is the only scope added to a token
  #     the token is for a "full trust" application
  def notify_owner_of_private_data_scopes(is_new_record:, is_regenerated:)
    return if integration_application_type?
    return if oauth_application_authorization? && !Apps::Privileged.capable?(:notify_owner_of_private_data_scopes, app: application)
    previous_scopes = Array(previous_changes["scopes"]&.first)
    added_scopes = Array(previous_changes["scopes"]&.last) - previous_scopes

    # Is a user authing into an app for the first time?
    new_app_authorization = is_new_record && !personal_access_authorization?

    # alert on all changes to PATs where scopes are created/added
    pat_with_added_scopes = personal_access_authorization? && added_scopes.any?

    # alert on OAuth apps with added scopes so long as the added scope isn't ONLY read:user
    added_scopes_are_risky = !added_scopes.to_set.subset?(PUBLIC_DATA_SCOPES)
    oauth_app_with_added_scopes = oauth_application_authorization? && added_scopes.any? && added_scopes_are_risky

    if new_app_authorization || pat_with_added_scopes || oauth_app_with_added_scopes || is_regenerated
      AccountMailer.oauth_authorization_notification(
        authorization: self,
        added_scopes: added_scopes,
        previous_scopes: previous_scopes,
        is_new_record: is_new_record,
        is_regenerated: is_regenerated,
      ).deliver_later
    end
  end

  # Private: sends notification email to owner that has authorized a GitHub app
  # with a certain set of user permissions
  def notify_owner_of_github_app_with_new_user_permissions
    return unless integration_application_type?
    return if Apps::Privileged.capable?(:skip_notification_of_user_permission_changes, app: application)
    return unless integration_version.present?
    return unless integration_version.user_permissions.any?

    IntegrationMailer.authorized(authorization: self).deliver_later
  end

  # Private: sends notification email to owner that has authorized a GitHub app
  # which permissions have been upgraded since the last time it was authorized
  def notify_owner_of_github_app_with_upgraded_user_permissions
    return unless integration_application_type?
    return if Apps::Privileged.capable?(:skip_notification_of_user_permission_changes, app: application)
    return unless previous_changes.include?(:integration_version_number)

    previous_version_number = previous_changes[:integration_version_number][0]
    previous_version        = application.versions.find_by(number: previous_version_number)

    IntegrationMailer.re_authorized(authorization: self, previous_version: previous_version).deliver_later
  end
end
