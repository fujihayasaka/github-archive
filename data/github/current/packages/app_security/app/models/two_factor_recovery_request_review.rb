# typed: true
# frozen_string_literal: true

class TwoFactorRecoveryRequestReview
  include Instrumentation::Model

  attr_reader :message, :reason, :type, :audit_entry_time

  AUTOMATED_REVIEW_PREFIX = "two-factor-recovery-request-review"

  # user_email.unverify is only logged when bounces occur.
  # This means the user could not take this action on their own accord,
  # so we are not tracking it.
  EMAIL_ACTIONS_NEW_ACCOUNT_EXPECTED = %w(user.add_email user_email.confirm_verification email_role.create).freeze
  EMAIL_ACTIONS_NEW_ACCOUNT_UNEXPECTED = %w(user.remove_email).freeze
  EMAIL_ACTIONS = [].concat(EMAIL_ACTIONS_NEW_ACCOUNT_EXPECTED, EMAIL_ACTIONS_NEW_ACCOUNT_UNEXPECTED)

  UNRECOGNIZED_LOCATION_ACTIONS = %w(user.correct_password_from_unrecognized_device_and_location user.correct_password_from_unrecognized_location).freeze
  SECURITY_ACTIONS = %w(public_key.create user.rename user.change_password).freeze
  AUTOMATIC_FLAG_ACTIONS = %w(user.initiate_two_factor_recovery_without_password).freeze
  POTENTIAL_TAKEOVER_INDICATORS = [].concat(UNRECOGNIZED_LOCATION_ACTIONS, SECURITY_ACTIONS, AUTOMATIC_FLAG_ACTIONS)
  POST_REQUEST_FLAGGED_ACTIONS = %w(user.login two_factor_authentication.disabled two_factor_authentication.enabled).freeze

  ACTIONS_LIST = [].concat(EMAIL_ACTIONS, POTENTIAL_TAKEOVER_INDICATORS, POST_REQUEST_FLAGGED_ACTIONS)

  SPONSOR_COUNT_THRESHOLD = 100

  # Should be a whole-dollar amount, divisible by 100
  SPONSOR_LISTING_THRESHOLD_IN_CENTS = 5000_00

  # Should be a whole-dollar amount, divisible by 100
  SPONSORSHIP_TOTAL_THRESHOLD_IN_CENTS = 1000_00

  def initialize(request)
    @request = request
  end

  def event_payload
    payload = if @message.present?
      {
        user: @request.user,
        review_required: true,
        message: @message,
        type: @type,
        reason: @reason,
      }
    else
      {
        user: @request.user,
        review_required: false
      }
    end

    if GitHub.flipper[:recovery_without_password_flagging].enabled?(@request.user)
      payload[:without_password] = without_password
      payload[:two_factor_account_recovery_id] = @request.id
    end
    payload
  end

  def event_prefix
    :two_factor_account_recovery_review
  end

  def instrument_risk_assesment
    GitHub.dogstats.increment("two_factor_recovery_request_review.result", tags: ["review_required:#{review_required?}", "review_type:#{@type}"])
    instrument :risk_assessment
  end

  def instrument_hydro
    GlobalInstrumenter.instrument("automated_two_factor_account_recovery_request_review",
      user: @request.user,
      review_required: review_required?,
      reason_type: hydro_reason_type,
      audit_log_event_type: hydro_audit_log_event_type,
      email_status_type: hydro_email_status_reason_type,
      org_membership_type: hydro_org_membership_type,
    )
  end

  def request_type
    without_password ? "password_reset" : "login_2fa"
  end

  # TwoFactorRecoveryRequestReview#perform makes decisions about whether to automate a recovery request
  # or open a support ticket based upon these criteria in sequence

  # User type - if a User changes from a 'User' to an 'Organization' a manual review is required
  # Staff - any member of GitHub staff that requests two-factor recovery should be manually reviewed by Support.
  # Deceased - Deceased users will require manual review

  # Unverified primary emails - if the users primary email is bouncing it will require manual review
  # Unverified backup email - the same here, except with backup email
  # Disposable email addresses - the request is flagged for manual review if the account requesting
  # account recovery has any email address belonging to a domain with very low reputation (<0.1).

  # Audit log actions after completing request - If any of the following actions happen after
  # the recovery request is initiated a manual review is required
  # ** user.login
  # ** two_factor_authentication.disabled
  # ** two_factor_authentication.enabled

  # Changes to email settings - Any recent email changes before (past 30 days) or during
  # the two factor recovery flow are considered suspicious these are found in the audit log as
  # ** user.add_email
  # ** user.remove_email
  # ** user_email.confirm_verification
  # ** email_role.create

  # Audit log actions before completing request - If any of the following actions happen after
  # the recovery request is initiated a manual review may be required
  # ** user.correct_password_from_unrecognized_device_and_location
  # ** user.correct_password_from_unrecognized_location
  # ** public_key.create

  # GitHub Sponsors: A manual review is required for any user that is a part of GitHub Sponsors and satisfies any of the following criteria:
  # ** $5000+ tier
  # ** > $1000 monthly sponsorship
  # ** > 100 sponsors

  # Organization memberships -  a manual review is required for any user who is either the:
  # ** Last admin of organization requiring 2FA
  # ** Owner or billing manager of a business requiring 2FA

  def perform
    assess_risk
    review = event_payload.except(:user).merge({ performed_at: Time.now.to_s })
    review[:audit_entry_time] = @audit_entry_time if @audit_entry_time.present?
    TwoFactorRecoveryRequestReview.store(@request.id, review)

    instrument_risk_assesment
    instrument_hydro
  end

  def review_required?
    @message.present?
  end

  def hydro_reason_type
    return :AUDIT_LOG if @type == "audit_log"
    return :EMAIL_STATUS if @type == "email_status"
    return :STAFF if @type == "staff"
    return :ORGANIZATION_MEMBERSHIP if @type == "org_membership"
    return :DECEASED if @type == "deceased"
    return :SPONSORS if @type == "sponsors"
    return :DEVICE if @type == "device"
    return :WITHOUT_PASSWORD if @type == "without_password"

    :REASON_TYPE_UNKNOWN
  end

  def hydro_audit_log_event_type
    return "" unless @type == "audit_log"

    @reason || ""
  end

  def hydro_email_status_reason_type
    return :EMAIL_STATUS_TYPE_UNKNOWN unless @type == "email_status"

    return :PRIMARY_EMAIL_BOUNCING if @reason == "primary_email_bouncing"
    return :BACKUP_EMAIL_UNVERIFIED if @reason == "backup_email_unverified"
    return :DISPOSABLE_EMAIL if @reason == "disposable_email_found"
    return :LOW_REPUTATION_DOMAIN if @reason == "disreputable_email"

    :EMAIL_STATUS_TYPE_UNKNOWN
  end

  def hydro_org_membership_type
    return :ORGANIZATION_MEMBERSHIP_TYPE_UNKNOWN unless @type == "org_membership"

    return :LAST_ADMIN if @reason == "last_admin"
    return :BUSINESS_AFFILIATION if @reason == "business_affiliation"

    :ORGANIZATION_MEMBERSHIP_TYPE_UNKNOWN
  end

  def self.mget(ids)
    keys = ids.map { |id| get_cache_key(id) }

    # using an empty array here as the fallback block as it'll be treated like
    # an array of `nil` values in the zip below
    GitHub.dogstats.increment("authn_kv", tags: ["action:read", "callsite:2fa_recovery_request_review"])
    cached_values = GitHub::Authentication::KV.store.mget(keys).value { [] }

    result = {}

    # build up a hash of all non-null results found in cache
    ids.zip(cached_values) { |id, value| result[id] = JSON.parse(value) unless value.nil? }

    result
  end

  def self.store(id, review)
    key = get_cache_key(id)

    begin
      GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:2fa_recovery_request_review"])
      GitHub::Authentication::KV.store.set(key, review.to_json(dangerously_allow_all_keys: true), expires: 2.weeks.from_now)
    rescue GitHub::KV::UnavailableError
      GitHub.dogstats.increment("kv_unavailable", tags: { service_owner: :account_login, callsite: :two_factor_recovery_request_review_perform, action: :set })
      raise TwoFactorRecoveryRequestReview::TemporarilyUnavailableError.new("KV not available")
    end
  end

  def self.get_cache_key(id)
    "#{AUTOMATED_REVIEW_PREFIX}-#{id}"
  end

  private

  def assess_risk
    if @request.review_state == :evidence_missing
      @message = "Evidence used to complete the request is no longer present"
      @type = "evidence_missing"
      return
    end

    #  [ **** IMPORTANT **** ]

    # The ordering of our conditional checks is extremely important, as the review
    # process does not need to exhaust all checks. As soon as a problem is found,
    # the request is considered marked for manual review and no automation will
    # be performed.
    #
    # If a user is staff or deceased they need manual intervention - no exceptions.
    #
    # In any other case we render a staff reviewable list of emails in the approval
    # modal **ONLY** when their email settings are identified as a problem. We
    # need to ensure their email settings are checked first, as this method exits
    # as soon as a problem is identified.
    #
    # Since Organization memberships are the most resource intensive check
    # we have placed them last to lessen the burden on our MySQL clusters.
    #
    # Keep this in mind if adding any new checks to this flow
    user = @request.user
    begin
      return if check_user_state(user)
      return @type = "email_status" if check_emails(user)
      return @type = "audit_log" if check_audit_logs
      return @type = "sponsors" if check_sponsorships(user)
      return @type = "org_membership" if check_org_membership(user)
      return @type = "without_password" if !check_resolvable_password_risk(user) if GitHub.flipper[:recovery_without_password_flagging].enabled?(user)
    rescue Driftwood::TwirpUtil::Error, Faraday::TimeoutError => e
      Failbot.report(e)
      raise TwoFactorRecoveryRequestReview::TemporarilyUnavailableError.new("Audit logs not available to review recovery request")
    rescue StandardError => e # rubocop:todo Lint/GenericRescue
      Failbot.report(e)
      @message = e.message
      @type = "automated_review_process_failed"
    end
  end

  def timestamp_conversion(event)
    Time.at(event[:@timestamp] / 1000)
  end

  # Everything below this is mutable based on decisions we make
  # regarding information that can be used to automate decisions to approve /deny
  def recent_user_actions
    @recent_user_actions ||=
      Audit::Driftwood::Query.new_user_query({
        actor_id: @request.user.id,
        allowlist: ACTIONS_LIST,
        phrase: "created:>=#{30.days.ago.iso8601}",
        per_page: 100,
      }).execute.results
  end

  def recent_partial_login_actions
    @recent_partial_login_actions ||=
      Audit::Driftwood::Query.new_user_query({
        actor_id: @request.user.id,
        from: "sessions#create",
        allowlist: ["user.two_factor_requested"],
        phrase: "created:>=#{7.days.ago.iso8601}",
        per_page: 100,
      }).execute.results
  end

  # Retrieves the recovery request-related audit log events for the user since request was created
  def recovery_submit_user_actions
    @recovery_submit_user_actions ||=
      Audit::Driftwood::Query.new_user_query({
        user_id: @request.user.id,
        allowlist: ["two_factor_account_recovery.complete"],
        phrase: "created:>=#{@request.created_at.iso8601}",
        per_page: 100,
      }).execute.results
  end

  # Retrieves the recovery request-initiate audit log events for the user since request was created
  def recovery_initiate_user_actions
    @recovery_initiate_user_actions ||=
      Audit::Driftwood::Query.new_user_query({
        user_id: @request.user.id,
        allowlist: ["two_factor_account_recovery.start"],
        phrase: "created:>=#{@request.created_at.iso8601}",
        per_page: 100,
      }).execute.results
  end

  # Retrieves the recovery request initiate audit log event for the current request
  def recovery_initiate_user_action
    # find `two_factor_account_recovery.start` event for this request
    @recovery_initiate_user_action ||= recovery_initiate_user_actions.find do |e|
      @request.id == e[:two_factor_account_recovery_id]
    end
  end

  def without_password
    return @without_password if defined?(@without_password)

    # check if event was initiated from 2FA login (`start`) or password reset (`without_password`)
    @without_password = !(recovery_initiate_user_action && recovery_initiate_user_action[:controller_action] == "start")
    @without_password
  end

  def recovery_request_ip_addresses
    @recovery_request_ip_addresses ||= recovery_submit_user_actions.filter_map { |e| e[:actor_ip] if !e[:actor_ip].nil? }.uniq
  end

  def recovery_request_locations
    @recovery_request_locations ||= recovery_submit_user_actions.filter_map { |e| e[:actor_location] if !e[:actor_location].nil? }.uniq
  end

  # retrieves the successful login audit log events for the user in the past
  def past_login_user_actions
    @past_login_user_actions ||=
    Audit::Driftwood::Query.new_user_query({
      actor_id: @request.user.id,
      allowlist: ["user.login"],
      phrase: "created:<#{@request.created_at.iso8601}",
      per_page: 100,
    }).execute.results
  end

  def past_login_ip_addresses
    @past_login_ip_addresses ||= past_login_user_actions.filter_map { |e| e[:actor_ip] if !e[:actor_ip].nil? }.uniq
  end

  def past_login_locations
    @past_login_locations ||= past_login_user_actions.filter_map { |e| e[:actor_location] if !e[:actor_location].nil? }.uniq
  end

  # compare all actions and if the user has taken any actions since the request was initiated
  # support should review
  def flagged_actions?(actions)
    discover_flagged_actions(actions, POST_REQUEST_FLAGGED_ACTIONS).each do |action|
      if !is_flagged_risk_resolvable?(action)
        return action
      end
    end

    nil
  end

  def is_flagged_risk_resolvable?(action)
    check_flagged_account_self_recovered(action)
  end

  # a user.login event after recovery was started from the same IP/location as a recovery request event implies
  # recovery request was legit and the user had misplaced 2FA means, but then recovered a way of entry to acct.
  # We can ignore that user.login event as non-problematic
  def check_flagged_account_self_recovered(action)
    if action[:action] == "user.login" &&
      (recovery_request_ip_addresses.include?(action[:actor_ip]) || recovery_request_locations.include?(action[:actor_location]))
      GitHub.dogstats.increment("two_factor_recovery_request_review.resolvable_risk", tags: ["reason:account_self_recovered", "request_type:#{request_type}"])
      return true
    end

    false
  end

  # compare all actions and if an email was added, removed, upgraded or downgraded in the past 30 days
  # support should review
  # unless the account is < 30 days old in which case only review if there are actions not expected of new accounts
  def email_changes?(actions)
    if @request.user.created_at >= 30.days.ago
      discover_flagged_actions(actions, EMAIL_ACTIONS_NEW_ACCOUNT_UNEXPECTED).first
    else
      discover_flagged_actions(actions, EMAIL_ACTIONS).first
    end
  end

  # Are there any indications that someone may be attempting to take over this account?
  # The existence of specific events doesn't necessarily mean that the recovery request is invalid, so we apply
  # stronger logic to determine if the events are actual indicators of an ATO
  # Note: the heuristics used to generate "unrecognized device/location" events belong to Authentication Records, which
  # are deleted afer 9 months, so an "unrecognized" device/location could actually be a device/location that was used
  # by the account legitimately > 9 months ago
  def potential_takeover?(actions)
    discover_flagged_actions(actions, POTENTIAL_TAKEOVER_INDICATORS).each do |action|
      if !is_ato_risk_resolvable?(action, actions)
        return action
      end
    end

    nil
  end

  def is_ato_risk_resolvable?(action, actions)
    # we can resolve here when `check_resolvable_password_risk` is handling the risk assesment for password reset requests
    return GitHub.flipper[:recovery_without_password_flagging].enabled?(@request.user) if AUTOMATIC_FLAG_ACTIONS.include?(action[:action])

    check_ato_verified_device_and_historical_client_used(action) ||
    check_ato_weak_location_ato_heuristic(action, actions) ||
    check_ato_public_key_create_different_evidence(action)
  end

  # if request uses verified device and we can match potential takeover action's client id to a previous
  # successful login audit log, we're not concerned about the action.
  def check_ato_verified_device_and_historical_client_used(action)
    if @request.authenticated_device&.verified?
      if login_clients.include?(action[:client_id])
        GitHub.dogstats.increment("two_factor_recovery_request_review.resolvable_risk", tags: ["reason:verified_device_and_historical_client_used", "request_type:#{request_type}"])
        return true
      end
    end

    false
  end

  def login_clients
    past_login_user_actions.filter_map { |a| a[:client_id] if !a[:client_id].nil? }
  end

  # if potential takeover action is an "unrecognized location" event (weaker indicator of account takeover),
  # acct has no recent security-related activity recently, and action IP/location matches a previous login log,
  # we're not concerned about the action
  # the common scenario here is returning to GitHub after a hiatus, maybe moved a bit but no big changes
  def check_ato_weak_location_ato_heuristic(action, actions)
    if UNRECOGNIZED_LOCATION_ACTIONS.include?(action[:action]) &&
        discover_flagged_actions(actions, SECURITY_ACTIONS).empty? && matches_historical_location(action)
      GitHub.dogstats.increment("two_factor_recovery_request_review.resolvable_risk", tags: ["reason:weak_ato_location_heuristic", "request_type:#{request_type}"])
      return true
    end

    false
  end

  # if potential takeover action is "public_key.create" but request authenticated w/ a different evidence method,
  # we're not concerned about the action
  # (public key action primarily dangerous if it's tried to be used as method of verifying acct)
  def check_ato_public_key_create_different_evidence(action)
    if action[:action] == "public_key.create" &&
      (@request.secondary_evidence_method != "Public key" || @request.public_key_id != action[:public_key_id])
      GitHub.dogstats.increment("two_factor_recovery_request_review.resolvable_risk", tags: ["reason:public_key_create_different_evidence", "request_type:#{request_type}"])
      return true
    end

    false
  end

  # returns whether the given action's IP address or location matches any previous user.login audit log events
  def matches_historical_location(action)
    past_login_ip_addresses.include?(action[:actor_ip]) || past_login_locations.include?(action[:actor_location])
  end

  # return a list of audit log entry results that match the given set, empty if no matches
  def discover_flagged_actions(actions, set)
    actions.filter { |r| set.include?(r[:action]) }
  end

  def check_user_state(user)
    @message, @type = if user.type != "User"
      ["User type has been changed", "wrong_user_type"]
    elsif user.site_admin?
      ["User is staff member", "staff"]
    elsif user.deceased?
      ["User has been marked as deceased by staff", "deceased"]
    end

    review_required?
  end

  def check_emails(user)
    user_emails = user.emails
    verified_emails = user.emails.verified
    primary_email = user.primary_user_email

    @message, @reason = if !primary_email.verified? && primary_email.bouncing?
      ["Primary email #{primary_email} is marked as bouncing. This email address should be verified again, and this account should be reviewed manually.", "primary_email_bouncing"]
    elsif user.has_backup_email? && !user.backup_user_email.verified?
      ["Backup email #{user.backup_user_email} is not verified. This request should be reviewed manually to ensure we do not send an email to an unverified address.", "backup_email_unverified"]
    elsif verified_emails.empty?
      disposable_email = user_emails.detect { |email| email.disposable? }
      ["Disposable email #{disposable_email} found on account without any verified email addresses", "disposable_email_found"] if disposable_email.present?
    else
      reputation = T.cast(nil, T.untyped)
      disreputable_email = user.account_related_emails.sort_by { |e| e.primary? ? 1 : 0 }.detect do |user_email|
        email = user_email.to_s
        reputation = EmailDomainReputationRecord.reputation(email).reputation
        reputation < 0.1
      end
      ["Email #{disreputable_email} comes from a domain with low reputation (#{reputation})", "disreputable_email"] if disreputable_email.present?
    end

    review_required?
  end

  def check_audit_logs
    # fetch audit logs for the past month, then split it into two sections
    # [[actions_after_request_initiated], [actions_before_request_initiated]]
    actions_after_request_initiated, actions_before_request_initiated = recent_user_actions.partition { |r| timestamp_conversion(r) > @request.created_at }

    # Rails lets you validate that a value is set when you set it
    # Following this flow allows us to check `action` to see if it is set, and then immediately use it
    # if it is set.
    @message = if action = flagged_actions?(actions_after_request_initiated)
      "A #{action[:action]} event was found for this user in the audit log after this recovery request was initiated."
    elsif action = email_changes?(recent_user_actions)
      "A #{action[:action]} event was found for this user in the audit log for the email address: #{action[:email]}."
    elsif action = potential_takeover?(actions_before_request_initiated)
      "A #{action[:action]} event was found for this user in the audit log before starting this recovery request."
    end

    if action.present?
      @reason = action[:action]
      @audit_entry_time = timestamp_conversion(action)
    end

    review_required?
  end

  # evaluate the risk of requests initiated from the password reset (without password) recovery flow
  def check_resolvable_password_risk(user)
    # login 2FA account recovery requests (with password) have no password risk
    return true if !without_password

    risk_resolvable = false
    if recovery_initiate_user_action.nil?
      @message, @reason = ["Recovery request audit log context is missing.", "password_context_missing"]
    elsif recovery_initiate_user_action[:controller_action] == "without_password"
      return true if recent_successful_partial_login(user) && GitHub.flipper[:recovery_without_password_partial_login_auto].enabled?(@request.user)
      @message ||= "Recovery request was initiated without user password."
      @reason ||= "without_password"
    else
      @message, @reason = ["Recovery request was initiated from unknown entry point.", "password_context_unexpected"]
    end

    risk_resolvable
  end

  # check if user has recent partial login event from the same client ID as this recovery request
  def recent_successful_partial_login(user)
    # no partial login events that don't match the request's client ID or any previous full logins
    non_matching_partial_login_clients = recent_partial_login_actions.filter_map do |a|
      a[:client_id] if a[:client_id] != recovery_initiate_user_action[:client_id] && !login_clients.include?(a[:client_id])
    end

    if non_matching_partial_login_clients.present?
      @message, @reason = ["Partial login event found from different client ID.", "password_usage_from_different_device"]
      return false
    end

    # password proof from within 30 min of request submission
    partial_login_clients = recent_partial_login_actions.filter_map do |a|
      a[:client_id] if a[:client_id] == recovery_initiate_user_action[:client_id] &&
        timestamp_conversion(a) < @request.created_at &&
        timestamp_conversion(a) > @request.created_at - 30.minutes
    end

    return false if partial_login_clients.empty?
    GitHub.dogstats.increment("two_factor_recovery_request_review.resolvable_risk", tags: ["reason:password_reset_request_with_associated_partial_login", "request_type:#{request_type}"])
    true
  end

  def check_org_membership(user)
    last_org_admin = user.affiliated_organizations_with_two_factor_requirement.select do |org|
      org.last_admin?(user)
    end

    @message, @reason = if last_org_admin.present?
      ["User is last admin of at least one organization", "last_admin"]
    elsif user.affiliated_businesses_with_two_factor_requirement.present?
      ["User is affiliated with business that requires 2FA", "business_affiliation"]
    end

    review_required?
  end

  def check_sponsorships(user)
    listing_ids = SponsorsListing.where(sponsorable_id: user.id).pluck(:id)

    published_tiers_above_threshold = SponsorsTier
      .for_listing(listing_ids)
      .where(state: 1) # published
      .where("monthly_price_in_cents > ?", SPONSOR_LISTING_THRESHOLD_IN_CENTS)
      .count > 0

    if published_tiers_above_threshold
      dollar_limit = Billing::Money.new(SPONSOR_LISTING_THRESHOLD_IN_CENTS).format
      @message = "User has published sponsorship tier over #{dollar_limit} per month"
      @reason = "high_sponsor_tier"
      return true
    end

    sponsorships = Sponsorship.all_active_as_sponsorable(sponsorable: user)

    if sponsorships.count > SPONSOR_COUNT_THRESHOLD
      @message = "User has #{sponsorships.count} active sponsors"
      @reason = "high_sponsor_count"
      return true
    end

    total_sponsorships_per_month_in_cents = sponsorships
      .map { |s| s.subscription_item.monthly_price_in_cents }
      .sum

    if total_sponsorships_per_month_in_cents >= SPONSORSHIP_TOTAL_THRESHOLD_IN_CENTS
      dollar_value = Billing::Money.new(total_sponsorships_per_month_in_cents).format
      @message = "User requesting account recovery receives significant amount " \
        "from sponsors: #{dollar_value} per month"
      @reason = "high_monthly_sponsorship"
    end

    review_required?
  end

  class TemporarilyUnavailableError < StandardError; end
end
