# typed: strict
# frozen_string_literal: true

module TradeControls::AbstractTradeScreeningDependency
  include GitHub::FlipperActor
  include GitHub::VexiActor
  include GitHub::Memoizer
  include Kernel
  extend T::Helpers

  abstract!

  # This is a comprehensive list of screening statuses that are prohibited from conducting commercial transactions.
  TRADE_SCREENING_RESTRICTED_STATUS = T.let((
    AccountScreeningProfile::BLOCKED_STATUSES.map(&:to_s) + AccountScreeningProfile::SDN_DATA_ISSUE_STATUSES
  ).freeze, T::Array[String])

  STAFF_ACTION = "Staff action: "

  # Public: Checks if Live SDN screening is enabled for the trade screening record owner
  sig { overridable.returns(T::Boolean) }
  def live_sdn_screening_enabled?
    self.feature_flag_enabled?(:live_sdn_screening, default: true)
  end

  # Public: Returns the has_one :trade_screening_record association for this actor.
  #
  # If the associated record doesn't exist, it falls back to building a new
  # one. This ensures callers do not need the safe-navigation operator. It
  # also ensures a consistent API between Users with an `not_screened` record
  # and those without an associated screening at all; as those two scenarios
  # are semantically the same.
  #
  # WARNING: Don't call this method directly to check if the actor can perform a
  # commercial transaction. That is, don't do `trade_screening_record.msft_trade_screening_status`.
  # This is especially true when the target is an Organization or Business in which case we need to
  # ensure that both the org/business and the current user have a non-blocking status. Instead, use
  # `check_trade_compliance` for GET or POST requests.
  # Without this, in the scenario where the org/business has a non-blocking status but
  # the user does not, this method will return the non-blocking record because of the order of precedence.
  sig { overridable.params(ignore_linked_record: T::Boolean).returns(AccountScreeningProfile) }
  def trade_screening_record(ignore_linked_record: false)
    super() || T.cast(self, Billing::Types::Account).build_trade_screening_record(owner: self)
  end

  # Public: check if business has a valid personal profile for financial transactions with any of the address fields entered
  sig { overridable.returns(T::Boolean) }
  def has_saved_trade_screening_record_with_information?
    false
  end

  # Public: check if user has a persisted and valid screening record
  sig { overridable.params(skip_validation_errors: T::Boolean).returns(T::Boolean) }
  def has_saved_trade_screening_record?(skip_validation_errors: false)
    return true if has_commercial_interaction_restriction?(feature_type: :update_info)
    valid_trade_screening_details?
  end

  # Public: Does the account have llama2 access request metadata
  sig { overridable.returns(T::Boolean) }
  def has_requested_llama2_access?
    trade_screening_record.owner_has_requested_llama2_access?
  end

  # Public: Does the account have a screening restriction that forbids account deletion
  sig { overridable.returns(T::Boolean) }
  def trade_compliance_account_delete_restriction?
    trade_screening_record.delete_restricted?
  end

  sig { overridable.returns(T::Boolean) }
  def trade_compliance_pii_delete_restriction?
    trade_screening_record.has_delete_pii_trade_restrictions?
  end

  # Public: Does the account have a trade screening true match restriction
  sig { overridable.returns(T::Boolean) }
  def trade_compliance_true_match_restricted?
    trade_screening_record.is_true_match_restricted?
  end

  # Public: Checks if an actor has been previously trade screened
  sig { returns(T::Boolean) }
  def trade_compliance_screened?
    return true unless live_sdn_screening_enabled?
    !trade_screening_record.not_screened?
  end

  # Public: Returns the screening record trade screening status from MSFT
  sig { overridable.returns(String) }
  def trade_screening_status
    trade_screening_record.msft_trade_screening_status
  end

  # Public: only used when an actor has a commercial interaction restriction
  # to get the restriction notice
  sig { overridable.returns(Symbol) }
  def trade_screening_status_notice
    if trade_screening_record.is_true_match_restricted?
      :trade_screening_true_match_notice
    else
      :trade_screening_generic_notice
    end
  end

  sig { overridable.params(address_type: String).returns(T.untyped) }
  def contact_information_stash(address_type)
    Billing::ContactUpdateStash.retrieve_stashed_update_for(T.cast(self, Billing::Types::Account), address_type)
  end

  # Public: Used to check if a re-screening should be performed for an actor.
  # This is called after an actor updates their PII data
  sig { overridable.returns(T::Boolean) }
  def should_perform_live_sdn_rescreening?
    live_sdn_screening_enabled? && trade_screening_record.last_trade_screen_date.present?
  end

  # Public: Checks if vat code is required for the record based on the country
  sig { overridable.returns(T::Boolean) }
  def vat_code_required_geo?
    org_is_on_business_tos? && ::TradeControls::Countries.vat_code_required_geo?(trade_screening_record.country_code)
  end

  # Public: Checks if postal code is required for the record based on the country
  sig { overridable.returns(T::Boolean) }
  def postal_code_required_geo?
    trade_screening_record.postal_code_required_geo?
  end

  # Public: Performs call to SDN Live API service and saves new status.
  sig do
    overridable
      .params(
        force: T::Boolean,
        account_screening_profile: T.nilable(AccountScreeningProfile),
        feature_type: Symbol,
        metadata: T::Hash[T.untyped, T.untyped]
      )
      .returns(T::Boolean)
  end
  def perform_live_sdn_screening(force: false, account_screening_profile: nil, feature_type: :default, metadata: {})
    return !has_commercial_interaction_restriction?(feature_type: feature_type) unless should_perform_live_sdn_screening?(force: force)

    # The following is to ensure we default to using the updated account screening profile if it exists,
    # which will only happen if this is a re-screening call when the actor has updated their PII data.
    record_to_screen = T.let(account_screening_profile.presence, T.nilable(AccountScreeningProfile)) || trade_screening_record
    return false if perform_spammy_live_request(record_to_screen: record_to_screen)

    # Wrap the API call so that we can easily return the commercial restriction status
    begin
      response = request_trade_screening(record_to_screen: record_to_screen)
      return !has_commercial_interaction_restriction?(feature_type: feature_type) if response.nil?

      save_trade_screening_response(response: response, metadata: record_to_screen.metadata.merge(metadata))
      instrument_result_to_hydro(response, record_to_screen)
    rescue TradeCompliance::TradeScreening::ApiServiceError, ArgumentError => e
      initiate_retry_for_failed_screening(error: e, record_to_screen: record_to_screen)
    end

    !has_commercial_interaction_restriction?(feature_type: feature_type)
  end

  # Public: returns true or false dependent on whether the actor is allowed to
  # update their billing information. The actor is only allowed to update
  # their information if their screening status is part of the SDN_STATUS_UPDATE_ALLOW_LIST.
  sig { overridable.returns(T::Boolean) }
  def is_allowed_to_edit_billing_information?
    T.bind(self, Billing::Types::Account)
    billing_contact_exists = if feature_flag_enabled?(:read_billing_information_from_contacts, default: false)
      billing_contact.persisted?
    else
      has_saved_trade_screening_record?(skip_validation_errors: true)
    end
    return false unless billing_contact_exists
    return true unless live_sdn_screening_enabled?

    !billing_contact.has_update_trade_restrictions?
  end

  sig { overridable.returns(T::Boolean) }
  def is_allowed_to_remove_billing_information?
    T.bind(self, Billing::Types::Account)
    billing_contact_exists = if feature_flag_enabled?(:read_billing_information_from_contacts, default: false)
      billing_contact.persisted?
    else
      has_saved_trade_screening_record?(skip_validation_errors: true)
    end
    return false unless billing_contact_exists

    !billing_contact.has_delete_pii_trade_restrictions?
  end

  sig { returns(T::Boolean) }
  def has_update_trade_restrictions?
    trade_screening_record.has_update_trade_restrictions?
  end

  # Public: Checks if this user is allowed to be automatically approved as sponsorable.
  # They are only allowed to be auto approved if their SDN (special designated national) screening
  # status is part of the account screening profile SDN_ALLOWED_AUTO_SPONSORSHIP_LIST.
  sig { abstract.returns(T::Boolean) }
  def has_sdn_auto_sponsorable_restrictions?; end

  # Public: Used to check if an actor is allowed to have commercial interactions.
  # This check excludes `retry` screening status, and therefore, returns false
  # in such case.
  sig(:final) { params(feature_type: Symbol).returns(T::Boolean) }
  def has_commercial_interaction_restriction?(feature_type: :default)
    owner_has_sdn_restriction?(feature_type: feature_type)
  end

  # Public: Used to check if an actor has been properly screened against the
  # Live SDN API and has a blocking status.
  sig(:final) { params(feature_type: Symbol).returns(T::Boolean) }
  def has_trade_screening_restriction?(feature_type: :default)
    has_commercial_interaction_restriction?(feature_type: feature_type)
  end

  # Public: Used to check if an actor is allowed to have commercial interactions.
  # This check does not exclude any screening statuses.
  sig { overridable.returns(T::Boolean) }
  def has_strict_commercial_interaction_restriction?
    return false unless live_sdn_screening_enabled?
    return false unless trade_compliance_screened?

    !trade_screening_record.sdn_status_allowed?
  end

  sig { overridable.returns(T::Array[String]) }
  def sdn_restricted_status_list
    TRADE_SCREENING_RESTRICTED_STATUS
  end

  # Public: used to check if the owner of the trade screening record is on
  # business terms of service
  sig { overridable.returns(T::Boolean) }
  def org_is_on_business_tos?
    false
  end

  # Public: used to check if the org owner of the trade screening record is on
  # standard terms of service
  sig { overridable.returns(T::Boolean) }
  def org_is_on_standard_tos?
    false
  end

  # Public: Returns object type for instrumentation logging
  sig { abstract.returns(Symbol) }
  def instrumentation_object_type; end

  # Public: Used to provide a human readable trade screening status
  sig { overridable.params(authorized_staffer: T::Boolean).returns(String) }
  def humanize_trade_screening_status(authorized_staffer: false)
    status = authorized_staffer ? " (#{trade_screening_record.msft_trade_screening_status})" : ""
    if trade_screening_record.not_screened?
      "Unknown#{status} restrictions. Account has not been screened for commercial interaction restrictions"
    elsif trade_screening_record.sdn_status_allowed?
      "No#{status} restrictions. Account is approved for commercial interactions"
    elsif trade_screening_record.hit_in_review?
      "Pending#{status} restrictions. Account is under review for commercial interaction restrictions"
    elsif trade_screening_record.ingestion_error? || trade_screening_record.data_issue?
      "Error#{status}. Account encountered an issue with their billing information while screening for commercial interaction restrictions. The owner of the account should verify their billing information is accurate before attempting to proceed with the commercial interaction"
    elsif trade_screening_record.error? || trade_screening_record.retry?
      "Error#{status}. Account encountered an issue while screening for commercial interaction restrictions. Reach out to #trade-compliance / Trade Restriction team for assistance"
    elsif trade_screening_record.spammy?
      "Restricted#{status}. Account is currently marked as spammy by GitHub and is ineligible for any commercial interactions"
    elsif trade_screening_record.is_true_match_restricted?
      "Restricted#{status}. Account is ineligible for any commercial interactions"
    elsif trade_screening_record.lic_r? || trade_screening_record.true_match?
      "Restricted#{status}. Account is ineligible for any new commercial interactions but can maintain and edit existing commercial interactions"
    else
      "Some#{status} restrictions. Account has some commercial interaction restrictions. Reach out to #trade-compliance / Trade Restriction team for assistance"
    end
  end

  sig { overridable.params(feature_type: Symbol).returns(T::Boolean) }
  def show_trade_screening_flash_notice?(feature_type: :default)
    TRADE_SCREENING_RESTRICTED_STATUS.exclude?(trade_screening_status)
  end

  sig { overridable.params(attrs: T::Hash[T.any(Symbol, String), T.untyped], ignore_linked_record: T::Boolean).returns(T::Boolean) }
  def update_trade_screening_record(attrs, ignore_linked_record: false)
    ActiveRecord::Base.connected_to(role: :writing) { trade_screening_record(ignore_linked_record: ignore_linked_record).update(attrs) }
  end

  # Public: Adds a suspension staff note to the account
  sig { overridable.params(note: String).void }
  def add_sdn_suspension_staff_note(note: "")
    suspension_note = "DO NOT MODIFY THIS ACCOUNT WITHOUT APPROVAL FROM TRADE SUPPORT/CELA. #{note}".strip
    self.add_staff_note(note: suspension_note)
  end

  # Public: Adds an unsuspension staff note to the account
  sig { overridable.params(note: String).void }
  def add_sdn_unsuspension_staff_note(note: "Account is no longer SDN suspended")
    self.add_staff_note(note: note)
  end

  # Public: Creates a link between a Standard Terms of Service organization and an admin user's screening record.
  # The link allows a Standard Terms of Service organization to depend on the admin's screening record for SDN
  # and commercial interaction checks.
  #
  # organization - the target Standard Terms of Service organization
  # screening_flow - the context from which the linking is being done
  sig { overridable.params(organization: Organization, screening_flow: T.nilable(T.any(Symbol, String))).returns(T::Boolean) }
  def link_trade_screening_record_to_org(organization:, screening_flow: nil)
    false
  end

  # Public: Removes the link between a Standard Terms of Service organization and an admin user's screening record.
  #
  # organization - the target Standard Terms of Service organization
  sig { overridable.params(organization: Organization).returns(T::Boolean) }
  def unlink_trade_screening_record_from_org(organization:)
    false
  end

  # Public: Removes the billing link for a Standard Terms of Service organization.
  #
  # reason - the reason for unlinking the record
  sig { overridable.params(reason: String).returns(T::Boolean) }
  def unlink_trade_screening_record_from_org_without_actor(reason:)
    false
  end

  # Public: Checks if the org on Standard Terms of Service has a linked trade screening record
  sig { overridable.returns(T::Boolean) }
  def has_linked_trade_screening_record?
    false
  end

  # Public: Checks if the admin user has a trade screening record which is linked to an organization on
  # standard terms of service
  #
  # organization - the target Standard Terms of Service organization
  sig { overridable.params(organization: Organization).returns(T::Boolean) }
  def has_trade_screening_record_linked_to_org?(organization:)
    false
  end

  # Public: Suspend the user in compliance with SDN (specially designated nationals) protocols.
  # This type of suspension performs the following:
  #   * Suspends the user
  #   * Locks private repositories
  #   * Archives public repositories
  #   * Places a legal hold on the account
  #
  # staff_user: The staffer who is suspending the actor.
  # reason: reason for the suspension
  sig { abstract.params(staff_user: User, reason: String).returns(T::Boolean) }
  def sdn_suspend(staff_user:, reason:); end

  # Public: SDN unsuspends an actor. This action is called through stafftools.
  #
  # staff_user: The staffer who is unsuspending the actor.
  # reason: reason for the unsuspension
  sig { abstract.params(staff_user: User, reason: String).returns(T::Boolean) }
  def sdn_unsuspend(staff_user:, reason:); end

  sig { abstract.returns(T::Boolean) }
  def sdn_suspended?; end

  sig { abstract.void }
  def send_sponsors_maintainer_restricted_email; end

  # Public: returns the full screening details for the customer, including all contacts
  # used to build the request to the trade screening API
  sig { overridable.params(record_to_screen: AccountScreeningProfile).returns(TradeCompliance::TradeScreening::ScreeningDetails) }
  def trade_screening_details(record_to_screen: trade_screening_record)
    screening_details = record_to_screen.screening_details
    contacts = record_to_screen.owner_contacts
    contacts.each { |contact| screening_details.add_customer_details(details: contact.customer_details) }
    screening_details
  end

  # Public: Checks if the trade screening record has valid details for screening
  # This is used to determine if the record can be screened or if it needs to be updated
  # before screening.
  sig { overridable.returns(T::Boolean) }
  def valid_trade_screening_details?
    return false if feature_flag_enabled?(:read_billing_information_from_contacts, default: false) && trade_screening_record.owner_contacts.blank?
    return false unless ensure_trade_screening_record_exists
    screening_details = trade_screening_details
    invalid_fields = screening_details.validate
    invalid_fields.empty?
  end

  private

  sig { overridable.returns(T::Boolean) }
  def ensure_trade_screening_record_exists
    T.bind(self, Billing::Types::Account)
    # external_uuid is used by the microsoft BIS API to track the request. We want to ensure that we have a unique value
    # save to the record so that we can track the request in the event of a failure or future updates from the API.
    update_trade_screening_record({ external_uuid: SecureRandom.uuid }) if trade_screening_record.persisted? && trade_screening_record.external_uuid.blank?

    return true if trade_screening_record.persisted?
    return false unless feature_flag_enabled?(:read_billing_information_from_contacts, default: false)

    attrs_to_update = {
      city: "",
      country_code: "",
      address1: "",
      address2: "",
      postal_code: "",
      region: "",
      last_trade_screen_date: Time.now.utc,
    }

    ActiveRecord::Base.connected_to(role: :writing) do
      begin
        # TODO this can be simplified to find_or_create_by once billing migration is complete
        # we have to do it this way right now to be able to skip validations
        record = AccountScreeningProfile.find_or_initialize_by(owner: self)
        if record.new_record?
          record.assign_attributes(attrs_to_update)
          record.save(validate: false)
        end
      rescue ActiveRecord::RecordNotUnique
        # This is fine, we just need a record to be persisted
      end

      # Reload the trade_screening_record association to avoid read replica lag
      association(:trade_screening_record).reload
    end

    true
  end

  sig { overridable.params(record_to_screen: AccountScreeningProfile).returns(T::Boolean) }
  def perform_spammy_live_request(record_to_screen:)
    false
  end

  sig { overridable.params(record_to_screen: AccountScreeningProfile).returns(T.nilable(TradeCompliance::TradeScreening::LiveResponse)) }
  def request_trade_screening(record_to_screen:)
    T.bind(self, Billing::Types::Account)

    screening_details = trade_screening_details(record_to_screen:)
    invalid_fields = screening_details.validate
    return TradeCompliance::TradeScreening::ApiService.request_trade_screening(hydro_actor: record_to_screen.hydro_actor, screening_details: screening_details) unless invalid_fields.any?

    log_screening_request_validation_errors(invalid_fields: invalid_fields.join(", "))
    nil
  end

  sig { overridable.params(error: StandardError, record_to_screen: AccountScreeningProfile).void }
  def initiate_retry_for_failed_screening(error:, record_to_screen:)
    if record_to_screen.msft_trade_screening_status == "retry"
      # The record has already been retried, and it failed so we just log
      GitHub.dogstats.increment("sdn_api_service.screened.retry.failed", tags: ["reason:#{error.message}"])
      return
    end

    # Next, we want to update the screening status to 'retry' so the background job can pick it up and retry the screening
    retry_reason = error.message.presence || "Unknown error"
    response = TradeCompliance::TradeScreening::LiveResponse.create_retry_response(external_uuid: trade_screening_record.external_uuid, status_reason: retry_reason)
    save_trade_screening_response(response: response, metadata: record_to_screen.metadata)

    # Do the logging thing to indicate that the initial request failed and we are retrying
    GitHub.dogstats.increment("sdn_api_service.screened.retry", tags: ["reason:#{retry_reason}"])
    GitHub.logger.error("sdn_api_service.screened.retry",
      "gh.sdn_api_service.retry_reason": retry_reason,
      "gh.sdn_api_service.existing_status": trade_screening_status,
      "gh.sdn_api_service.external_uuid": trade_screening_record.external_uuid
    )
  end

  sig { overridable.params(invalid_fields: String).void }
  def log_screening_request_validation_errors(invalid_fields:)
    message = "Screening record has invalid fields: #{invalid_fields}"
    error = AccountScreeningProfile::InvalidScreeningFieldsError.new(message)
    Failbot.report(error, user_id: trade_screening_record.external_uuid)
  end

  sig { overridable.params(message: String).void }
  def log_screening_response_errors(message:)
    error = AccountScreeningProfile::InvalidScreeningFieldsError.new(message)
    Failbot.report(error, user_id: trade_screening_record.external_uuid)
  end

  sig { overridable.params(response: TradeCompliance::TradeScreening::LiveResponse, metadata: T::Hash[String, T.untyped]).returns(T::Boolean) }
  def save_trade_screening_response(response:, metadata:)
    new_status = response.status
    status_reason = { "status_reason": response.status_reasons }
    attrs_to_update = {
      msft_trade_screening_status: new_status,
      metadata: metadata.merge(status_reason)
    }

    # we want to still be able to track the last time a screening was done
    # irrespective if the status is same as before.
    # Without doing below last_trade_screen_date won't be updated
    if trade_screening_status == new_status
      attrs_to_update[:last_trade_screen_date] = Time.now.utc
    end

    # TODO: Once we migrate billing info out of the trade screening table we can rely on #save_contact_response instead
    # see https://github.com/github/trade-compliance/issues/1423
    billing_address_response = response.live_responses.find { |r| r.request_id == trade_screening_record.request_id }
    attrs_to_update[:billing_trade_screening_status] = billing_address_response.status if billing_address_response.present?

    update_trade_screening_record(attrs_to_update)

    live_responses = response.live_responses
    live_responses = live_responses.reject { |r| r.request_id == billing_address_response.request_id } if billing_address_response.present? && !self.feature_flag_enabled?(:read_billing_information_from_contacts, default: false)
    save_contact_responses(responses: live_responses)
  end

  sig { overridable.params(responses: T::Array[TradeCompliance::TradeScreening::LiveResponse]).returns(T::Boolean) }
  def save_contact_responses(responses:)
    saved_all_contacts = T.let(true, T::Boolean)
    request_ids = responses.map(&:request_id)
    trade_screening_record.owner_contacts.each do |contact|
      response = responses.find { |r| r.request_id == contact.trade_screening_request_id }

      if response.nil?
        request_ids << contact.trade_screening_request_id
        saved_all_contacts = false
        next
      end

      request_ids.delete(contact.trade_screening_request_id) if response.present?
      ActiveRecord::Base.connected_to(role: :writing) do
        contact.update(trade_screening_status: response.status)
      end
    end

    if request_ids.any?
      error = "Missing contact request ids: #{request_ids.join(", ")}"
      log_screening_response_errors(message: error.to_s)
    end

    saved_all_contacts
  end

  # Private: Instruments the trade screening response to Hydro for analytics
  sig { overridable.params(result: TradeCompliance::TradeScreening::LiveResponse, upp: AccountScreeningProfile).void }
  def instrument_result_to_hydro(result, upp)
    GlobalInstrumenter.instrument("sdn_trade_screening.result_available", {
      country: upp.country_code,
      external_user_id: result.external_uuid,
      request_id: result.eid,
      request_type: :LIVE,
      status: result.status,
      actor_type: upp.hydro_actor
    })
  end

  # Private: Used to check if screening should be performed for an actor.
  # This is called when the goal is to screen an actor for the first time. eg in before_hooks
  sig { overridable.params(force: T::Boolean).returns(T::Boolean) }
  def should_perform_live_sdn_screening?(force: false)
    return false unless live_sdn_screening_enabled?
    return false unless valid_trade_screening_details?

    trade_screening_record.not_screened? || force
  end

  # Private: Checks if the account has an SDN restriction applied to the specific feature type
  #
  # feature_type - a key from AccountScreeningProfile::FEATURE_TYPE_ALLOW_LISTS
  sig { overridable.params(feature_type: Symbol).returns(T::Boolean) }
  def owner_has_sdn_restriction?(feature_type: :default)
    return false unless live_sdn_screening_enabled?
    return false unless trade_compliance_screened?
    return false if trade_screening_record.retry?

    !trade_screening_record.sdn_status_allowed?(feature_type: feature_type)
  end

  # Private: Toggle the actor's SDN suspension status. Creates a screening profile if none
  # exist
  #
  # should_suspend - sets sdn suspension status to true_match if true, no_hit if false
  # reason - reason for the suspension
  sig { overridable.params(staff_user: User, should_suspend: T::Boolean, reason: String).returns(T::Boolean) }
  def toggle_sdn_suspension_status(staff_user:, should_suspend:, reason:)
    screening_record = trade_screening_record(ignore_linked_record: true)
    unlink_billing_contact(actor: staff_user) if is_a?(Organization)

    attrs_to_update = {}
    attrs_to_update = {
      city: "",
      country_code: "",
      address1: "",
      address2: "",
      postal_code: "",
      region: "",
      last_trade_screen_date: Time.now.utc,
    } unless screening_record.persisted?

    attrs_to_update[:msft_trade_screening_status] = if should_suspend
      "true_match"
    else
      "no_hit"
    end

    status_reason = { "status_reason": "#{STAFF_ACTION}#{reason}" }
    attrs_to_update[:metadata] = screening_record.metadata.merge(status_reason)
    update_trade_screening_record(attrs_to_update, ignore_linked_record: true)
  end

  # Private: Adds a staff note to the account
  #
  # Will log to sentry if the staff note could not be saved
  sig { overridable.params(note: String).void }
  def add_staff_note(note:)
    user = User.find_by_login("hubot") || User.ghost
    staff_note = StaffNote.new({ user: user, notable: self, note: note })

    # Record if we failed to add a staff note
    Failbot.report!(StandardError.new("failed to add sdn staff note")) unless staff_note.save
  end
end
