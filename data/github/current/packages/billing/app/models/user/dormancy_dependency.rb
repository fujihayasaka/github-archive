# typed: strict
# frozen_string_literal: true

module User::DormancyDependency
  extend T::Helpers

  extend ActiveSupport::Concern

  requires_ancestor { User }

  # This dependency implements various checks for account activity.
  # This "active" is used on github.com to help determine if an account name can
  # be released when a user requests one that has been taken.  On Enterprise it
  # is used to release paid seats for other users.
  #
  # There are different rules and timeframes used for dotcom and enterprise.
  # These are handled using the `GitHub.dormancy_threshold` setting, which is
  # passed to these functions.  You will find various `GitHub.enterprise?`logic
  # within these methods as well.
  #
  # The rules used for dotcom can be found at
  # https://support-kb.githubapp.com/support/compliance/usernames/supporting-username-requests/#evaluating-standard-username-requests

  ###########################
  ### NOTE TO MAINTAINERS ###
  ###########################
  # Logic for Organizations is different in some spots, if you are updating this
  # file do not forget to also update the org-specific overrides in
  # app/models/organization/dormancy_dependency.rb

  # Holds the results for the dormant user check on GHEC, where we include both business
  # members and outside collaborators
  class DormantUsersResult < T::Struct
    prop :members, T::Array[User], default: []
    prop :outside_collaborators, T::Array[User], default: []
  end

  class_methods do

    # Loads all Users who are currently considered dormant based on User#dormant?,
    # aren't suspended, and are not staff. This is used primarily in Enterprise
    # to generate reports that are used to determine which users are good candidates
    # for being suspended to free up seats.
    sig do
      params(
        threshold: ActiveSupport::Duration,
        timeout_seconds: T.nilable(Integer),
        business_id: T.nilable(Integer),
        no_dormancy_exemptions: T::Boolean,
        batch_size: Integer,
        business_report_export: T.nilable(BusinessReportExport)
      ).returns(T::Array[User])
    end
    def dormant_users(threshold: GitHub.dormancy_threshold, timeout_seconds: nil, business_id: nil, no_dormancy_exemptions: false, batch_size: 50, business_report_export: nil)
      conditions = [
        "login != ?
          AND type = 'User'
          AND suspended_at IS NULL
          AND IFNULL(gh_role, '') != 'staff'",
        GitHub.ghost_user_login,
      ]

      users = []
      start_time = Time.now
      current_batch_count = 0
      if business_id
        # With a business_id, we're running this report for GHEC clients on dotcom.
        business = Business.find(business_id)

        all_business_user_ids = BusinessUserAccount.where(business_id: business_id).pluck(:user_id)
        all_business_user_ids.in_groups_of(batch_size) do |business_user_ids_batch|
          business_user_ids_batch.compact! # in_groups_of pads with nil value

          # Get a list of user ids that are actually members of the business
          batch_member_ids = business.member_ids(actor_ids: business_user_ids_batch)
          batch_org_member_ids = business.organization_member_ids(actor_ids: business_user_ids_batch)
          business_member_ids_batch = (batch_member_ids + batch_org_member_ids).uniq

          # for some reason using the conditions in the user query
          # was making some executions slow (https://github.com/github/github/issues/203228)
          # so we query the table by primary key and then filter in memory
          business_users = User.where(id: business_member_ids_batch)
            .to_a
            .reject(&:suspended?)

          user_dormancy_by_business = business.feature_enabled?(:user_dormancy_by_business)
          business_users.each do |user|
            # capture time for both cases
            GitHub.dogstats.time("dormant_users.ghec_dormancy_check", tags: ["user_dormancy_by_business:#{user_dormancy_by_business}"]) do
              if user_dormancy_by_business
                users << user if user.dormant_within_business?(business: business, threshold: threshold)
              else
                users << user if user.dormant?(threshold, no_dormancy_exemptions: no_dormancy_exemptions)
              end
            end
          end
          current_batch_count += 1
          if Time.now >= start_time + 30.seconds && business_report_export.present?
            start_time = Time.now
            ActiveRecord::Base.connected_to(role: :writing) do
              business_report_export.update_status!(current_user_count: batch_size * current_batch_count, total_user_count: all_business_user_ids.count)
            end
            data = { status: business_report_export.status }
            channel_name = GitHub::WebSocket::Channels.business_report_export_status(business_report_export)
            GitHub::WebSocket.notify_business_report_export_status_channel(business_report_export, channel_name, data)
          end
        end
      else
        # Without a business_id, we're running this report for all users on a GHES instance.
        final_query = User.where(conditions)
        final_query.order("login ASC").to_a.each do |user|
          users << user if user.dormant?(threshold, no_dormancy_exemptions: no_dormancy_exemptions)
          break if timeout_seconds && Time.now >= start_time + timeout_seconds
        end
      end

      users
    end

    # Public, only used to create the user dormancy report for GHEC
    # Returns a list of members and outside collaborators for the given business.
    # Updates the given business_report_export and sends a websocket update after each batch
    # of users has been checked.
    sig { params(business_id: Integer, business_report_export: BusinessReportExport, threshold: T.nilable(Integer), batch_size: Integer).returns(DormantUsersResult) }
    def dormant_users_for_business(business_id:,  business_report_export:, threshold: GitHub.dormancy_threshold,  batch_size: 50)
      start_time = Time.now
      current_batch_count = 0

      # With a business_id, we're running this report for GHEC clients on dotcom.
      business = Business.find(business_id)

      all_business_user_ids = BusinessUserAccount
        .where(business_id: business_id)
        .pluck(:user_id)

      # IDs of users who are _exclusively_ outside collaborators
      outside_collaborator_ids = BusinessUserAccount
        .where(business_id: business_id)
        .exclusive_roles(:outside_collaborator)
        .pluck(:user_id)

      business_users_excluding_collabs_ids = all_business_user_ids - outside_collaborator_ids

      total_id_count = business_users_excluding_collabs_ids.count + outside_collaborator_ids.count

      results = DormantUsersResult.new

      business_users_excluding_collabs_ids.in_groups_of(batch_size) do |business_user_ids_batch|
        business_user_ids_batch.compact! # in_groups_of pads with nil value

        # Get a list of user ids that are actually members of the business
        batch_member_ids = business.member_ids(actor_ids: business_user_ids_batch)
        batch_org_member_ids = business.organization_member_ids(actor_ids: business_user_ids_batch)
        business_member_ids_batch = (batch_member_ids + batch_org_member_ids).uniq

        # for some reason using the conditions in the user query
        # was making some executions slow (https://github.com/github/github/issues/203228)
        # so we query the table by primary key and then filter in memory
        business_users = User.where(id: business_member_ids_batch)
          .to_a
          .reject(&:suspended?)

        business_users.each do |user|
          GitHub.dogstats.time("dormant_users.ghec_dormancy_check", tags: ["user_dormancy_by_business:true"]) do
            results.members << user if user.dormant_within_business?(business: business, threshold: threshold)
          end
        end
        current_batch_count += 1
        if Time.now >= start_time + 30.seconds && business_report_export.present?
          start_time = Time.now
          ActiveRecord::Base.connected_to(role: :writing) do
            business_report_export.update_status!(current_user_count: batch_size * current_batch_count, total_user_count: total_id_count)
          end
          data = { status: business_report_export.status }
          channel_name = GitHub::WebSocket::Channels.business_report_export_status(business_report_export)
          GitHub::WebSocket.notify_business_report_export_status_channel(business_report_export, channel_name, data)
        end
      end

      outside_collaborator_ids.in_groups_of(batch_size) do |outside_collaborator_ids_batch|
        outside_collaborator_ids_batch.compact! # in_groups_of pads with nil value

        # for some reason using the conditions in the user query
        # was making some executions slow (https://github.com/github/github/issues/203228)
        # so we query the table by primary key and then filter in memory
        collabs = User.where(id: outside_collaborator_ids_batch)
          .to_a
          .reject(&:suspended?)

        collabs.each do |user|
          GitHub.dogstats.time("dormant_users.ghec_dormancy_check", tags: ["user_dormancy_by_business:true"]) do
            results.outside_collaborators << user if user.dormant_within_business?(business: business, threshold: threshold)
          end
        end

        current_batch_count += 1
        if Time.now >= start_time + 30.seconds && business_report_export.present?
          start_time = Time.now
          ActiveRecord::Base.connected_to(role: :writing) do
            business_report_export.update_status!(current_user_count: batch_size * current_batch_count, total_user_count: total_id_count)
          end
          data = { status: business_report_export.status }
          channel_name = GitHub::WebSocket::Channels.business_report_export_status(business_report_export)
          GitHub::WebSocket.notify_business_report_export_status_channel(business_report_export, channel_name, data)
        end
      end

      results
    end
  end # class_methods block

  # Public: Check whether user fulfills dormancy guidelines
  sig do
    params(
      threshold: ActiveSupport::Duration,
      strict: T::Boolean,
      no_dormancy_exemptions: T::Boolean
    ).returns(T::Boolean)
  end
  def dormant?(threshold = GitHub.dormancy_threshold, strict: false, no_dormancy_exemptions: false)
    return !!@dormant if defined?(@dormant)

    @dormant = T.let(false, T.nilable(T::Boolean))

    @dormant = if no_dormancy_exemptions
      !recently_active?(threshold)
    else
      !exempt_from_dormancy?(threshold, strict: strict) && !recently_active?(threshold)
    end
  end

  # Public: Intended for use with GHEC users only, not GHES
  # This is the main method for public consumers.
  sig { params(business: Business, threshold: ActiveSupport::Duration).returns(T::Boolean) }
  def dormant_within_business?(business:, threshold: GitHub.dormancy_threshold)
    return !!@dormant_within_business if defined?(@dormant_within_business)

    GitHub.logger.with_named_tags("gh.business.id": business.id, "gh.user.id": id, "gh.dormant.method": "recent_activity_within_business") do
      ActiveRecord::Base.uncached do
        activity = recent_activity_within_business(business: business, threshold: threshold)
        GitHub.logger.info("Activity", "gh.dormant.activity" => activity.inspect)
        @dormant_within_business = T.let(activity.nil?, T.nilable(T::Boolean))
      end
    end
  end

  # Public: Intended for use with GHEC users only, not GHES
  #
  # This method is similar to `recently_active` but ignores things that we can't scope to an individual
  # business. It also returns the 'reason' for the activity to make later diagnostics easier.
  sig { params(business: Business, threshold: ActiveSupport::Duration).returns(T.nilable(T::Array[T.untyped])) }
  def recent_activity_within_business(business:, threshold: GitHub.dormancy_threshold)
    cutoff = Time.now - threshold
    created_at = self.created_at

    GitHub.logger.info("Checking created_at")

    return [:created_at, created_at] if created_at >= cutoff

    GitHub.logger.info("Checking billing transaction")
    if billing_time = last_billing_transaction_time_for_business(business)
      return [:billing_transaction, billing_time] if billing_time >= cutoff
    end

    GitHub.logger.info("Checking stratocaster events")
    if last_event = last_stratocaster_event_for_business_at(business)
      return [:stratocaster_event, last_event] if last_event >= cutoff
    end

    GitHub.logger.info("Checking audit log events")
    # Check the audit log for any non-failure events
    # The full list of events is here:
    # https://github.com/github/audit-log-allowlists/blob/8f1995a38ad2aa190a99f013c5a46eb7b15efe65/allowlists/user.json#L313

    # We've gotten some intermittent errors from the service, so we're going to
    # retry up to 2 times. If we still get an error, we'll just continue on and essentially
    # skip this user.
    retries = 0
    begin
      if last_audit_event = Audit::Driftwood::Query.get_business_user_dormancy_latest_timestamp(user_id: self.id, business_id: business.id)
        return [:audit_log_event, last_audit_event] if last_audit_event >= cutoff
      end
    # We don't want to fail the whole job invoking this method if we encounter an unexpected error for a given user.
    rescue StandardError => e # rubocop:todo Lint/GenericRescue
      # Still report the error so we can track it down later
      Failbot.report(e)
      retry if (retries += 1) < 3
      # We don't want to consider a user dormant just because we encountered an error.
      return [:driftwood_error, Time.now]
    end

    # Finally return nil if we cant' find any recent activity
    nil
  end

  sig { params(business: Business).returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def last_billing_transaction_time_for_business(business)
    return unless GitHub.billing_enabled?
    business.billing_transactions.merge(billing_transactions).last&.created_at
  end

  sig { params(business: Business).returns(T.nilable(Time)) }
  def last_stratocaster_event_for_business_at(business)
    business_org_ids = business.organizations.pluck(:id)

    event_ids = GitHub.stratocaster.ids(events_key)
    # Rather than loading all 300 events, we fetch them in batches to keep memory pressure low.
    business_events = event_ids.in_groups_of(50).flat_map do |batch|
      GitHub.stratocaster.ids_to_events(batch)
        .filter { |event| business_org_ids.include?(event.org_id) }
    end

    business_events.last&.created_at
  end

  # Public: Check if this account meets any conditions that would exempt it from
  # being flagged dormant regardless of activity.  For example, a user that has
  # no activity, but is paying us, would not be considered dormant
  sig { params(threshold: ActiveSupport::Duration, strict: T::Boolean).returns(T::Boolean) }
  def exempt_from_dormancy?(threshold = GitHub.dormancy_threshold, strict: false)
    # On Enterprise there are currently no rules for User exemption
    return false if GitHub.enterprise?

    # Giving us money is the simplest way to earn exemption
    return true if GitHub.billing_enabled? && plan.paid? && !disabled?

    # If a user has enabled 2FA, consider them exempt
    return true if two_factor_authentication_enabled?


    # If user has created any repositories (non-fork), consider them exempt
    return true if repositories.network_roots.count > 0

    # If any repos are active (have recent pushes), then the owner user is
    # active too.  We check this to ensure we don't disrupt an active repo that
    # has an otherwise dormant owner.
    return true if repositories.any? { |repo| !repo.dormant?(threshold) }

    # Wow, not paying and not part of an org?  OK well let's see what we have...
    return true if oauth_accesses.personal_tokens.any?
    return true if oauth_accesses.third_party.any?
    return true if public_keys.any?
    return true if member_repositories.any?

    if strict
      # owns any public packages
      return true if packages.any? { |package| package.repository_public? }
      # The strict dormancy critera specifies only active organizations matter
      return true if organizations.any? { |org| !org.dormant?(threshold) }

      # strict: any comments
      comments = {
        issue_comments: issue_comments.size,
        commit_comments: commit_comments.size,
        issues: issues.size,
      }
      return true if comments.values.sum > 0

      # strict: Gists
      return true if Gist.where(user_id: id).any?

      # strict: recently invited to an organization (audit log)
      last_org_invite_event = last_audit_log_entry_time_for_user_by_action("org.invite_member")
      return true if last_org_invite_event && last_org_invite_event >= Time.now - threshold
    else
      # On dotcom, being a member of any org earns an exemption
      return true if organizations.any?
    end

    false
  end

  sig { params(threshold: ActiveSupport::Duration).returns(T::Array[Organization]) }
  def active_organizations(threshold = GitHub.dormancy_threshold)
    organizations.reject { |org| org.dormant?(threshold) }
  end

  sig { params(threshold: ActiveSupport::Duration).returns(T::Array[Repository]) }
  def active_repositories(threshold = GitHub.dormancy_threshold)
    repositories.reject { |repo| repo.dormant?(threshold) }
  end

  # Public: Check if this account has any recent activity.  For example, a user
  # that has recently generated a dashboard event like a push or a star would be
  # considered "active"
  sig { params(threshold: ActiveSupport::Duration).returns(T::Boolean) }
  def recently_active?(threshold = GitHub.dormancy_threshold)
    cutoff = Time.now - threshold
    created_at = self.created_at

    # Creating an account is activity
    return true if created_at >= cutoff

    # Paying us (or attempting to) is activity
    last_bill = last_billing_transaction_time
    return true if last_bill && last_bill >= cutoff

    # Check for a recent session
    last_session = last_web_session_time
    return true if last_session && last_session >= cutoff

    # Starring a repo is activity
    last_star = last_repo_star_time
    return true if last_star && last_star >= cutoff

    # Watching a repo is activity if auto-watch is disabled
    unless GitHub.newsies.settings(self).auto_subscribe?
      last_watch = last_repo_watch_time
      return true if last_watch && last_watch >= cutoff
    end

    # Check for dashboard events, the most fundamental indicator of activity
    last_event = if T.unsafe(self).feature_enabled?(:conduit_user_dormancy)
      last_conduit_event_at
    else
      last_stratocaster_event_at
    end
    return true if last_event && last_event >= cutoff

    # Finally, check the audit log for any non-failure events
    # this includes logins, email verification and password resets
    last_audit_event = last_audit_log_entry_time_for_user_dormancy_actions
    return true if last_audit_event && last_audit_event >= cutoff

    # On GitHub Enterprise Server we also want to check for the last access
    # of personal access tokens and public keys to avoid counting service accounts
    # or read-only API (business) users as dormant.
    # Note that we exempt all users with personal access tokens and public keys on dotcom,
    # but not on GHES, see the "exempt_from_dormancy?" method
    if GitHub.enterprise?
      # Check for the last time a personal access token was used
      last_personal_token_access = last_personal_token_access_time
      return true if last_personal_token_access && last_personal_token_access >= cutoff

      # Check for the last time a public key was used
      last_public_key_access = last_public_key_access_time
      return true if last_public_key_access && last_public_key_access >= cutoff
    end

    false
  end

  # Public: Check whether user fulfills strict dormancy guidelines
  # For non-enterprise use, doesn't evaluate enterprise checks
  sig { params(threshold: ActiveSupport::Duration).returns(T::Hash[Symbol, T.untyped]) }
  def dormancy_status(threshold = GitHub.dormancy_threshold)
    @dormancy_status ||= T.let(build_dormancy_status(threshold), T.nilable(T::Hash[Symbol, T.untyped]))
  end

  ###########################
  ### NOTE TO MAINTAINERS ###
  ###########################
  # Logic for Organizations is different in some spots, if you are updating this
  # file do not forget to also update the org-specific overrides in
  # app/models/organization/dormancy_dependency.rb

  # Public: Compute whether user fulfills strict dormancy guidelines
  sig { params(threshold: ActiveSupport::Duration).returns(T::Hash[Symbol, T.untyped]) }
  def build_dormancy_status(threshold = GitHub.dormancy_threshold)
    # dormancy_status depends on all values being 0 or false
    dormancy_status = {}

    # default dormancy is 12 months (config.rb)
    dormancy_status[:created_at] = created_at

    # 2fa
    dormancy_status[:two_factor] = two_factor_authentication_enabled?

    paid = GitHub.billing_enabled? && plan.paid? && !disabled?
    dormancy_status[:paid] = paid

    dormancy_status[:last_transaction] = last_billing_transaction_time

    # If user has created any repositories (non-fork), consider them exempt
    dormancy_status[:repo_owner_count] = repositories.network_roots.count

    # If any repos are active (have recent pushes), then the owner user is
    # active too.  We check this to ensure we don't disrupt an active repo that
    # has an otherwise dormant owner.
    dormancy_status[:active_repo_owner] = repositories.any? { |repo| !repo.dormant?(threshold) }

    # Collaboration
    dormancy_status[:repo_member] = member_repositories.any?

    # strict: Gists
    dormancy_status[:gist_count] = Gist.where(user_id: id).count

    # Authed apps
    dormancy_status[:oauth_accesses] = oauth_accesses.personal_tokens.any? || oauth_accesses.third_party.any?

    # SSH keys
    dormancy_status[:public_keys] = public_keys.any?

    # strict: only membership to active orgs count
    dormancy_status[:active_org_membership_count] = organizations.to_a.count { |org| !org.dormant?(threshold) }

    # strict: public packages
    dormancy_status[:public_packages_count] = packages.to_a.count { |package| T.must(package.repository).public? }

    # Stars/Watching for a year
    dormancy_status[:last_star] = last_repo_star_time

    # Watching a repo is activity if auto-watch is disabled
    unless GitHub.newsies.settings(self).auto_subscribe?
      dormancy_status[:last_watch] = last_repo_watch_time
    end

    # Sessions for a year
    dormancy_status[:last_session] = last_web_session_time

    # Logins for a year
    last_login_event = last_audit_log_entry_time_for_user_by_action("user.login")
    dormancy_status[:last_login] = last_login_event

    # Password resets for a year
    last_reset_event = last_audit_log_entry_time_for_user_by_action("user.change_password")
    dormancy_status[:last_password_reset] = last_reset_event

    # Email verification for a year
    dormancy_status[:last_email_verification] = emails.maximum(:verified_at)

    # strict: all comments
    comments = {
      issue_comments: issue_comments.size,
      commit_comments: commit_comments.size,
      issues: issues.size,
    }
    dormancy_status[:all_comment_count] = comments.values.sum

    # strict: recent comments
    latest_comments = [
      issue_comments.maximum(:created_at),
      commit_comments.maximum(:created_at),
      issues.maximum(:created_at)
    ].reject(&:blank?)

    dormancy_status[:last_comment] = latest_comments.empty? ? nil : latest_comments.max

    # Check for dashboard events, the most fundamental indicator of activity
    dormancy_status[:last_event] = if T.unsafe(self).feature_enabled?(:conduit_user_dormancy)
      last_conduit_event_at
    else
      last_stratocaster_event_at
    end

    # Password resets, Email verification, Logins all covered by audit logs
    # Finally, check the audit log for any non-failure events
    dormancy_status[:last_log] = last_audit_log_entry_time_for_user_dormancy_actions

    # strict: recent invite to an organization (audit log)
    last_org_invite_event = last_audit_log_entry_time_for_user_by_action("org.invite_member")
    dormancy_status[:last_org_invite] = last_org_invite_event

    dormancy_status[:ignored] = {}
    dormancy_status[:ignored][:org_membership_count] = organizations.count
    dormancy_status[:ignored][:last_pass_compromise] = last_audit_log_entry_time_for_user_by_action("user.exact_email_and_password_match")

    # Set dormant to false if all keys are 0, nil, false, or a time before the cutoff
    dormancy_status[:active_keys] = dormancy_status.filter { |key, value| key != :ignored && !is_dormant_value(value, threshold) }.keys.sort

    if dormancy_status[:active_keys].empty?
      dormancy_status[:dormant] = true
    else
      dormancy_status[:dormant] = false
    end

    # information that we want to track but don't want to use to evaluate dormancy
    # all org memberships used to count towards dormancy
    dormancy_status
  end

  sig { params(val: T.untyped, threshold: ActiveSupport::Duration).returns(T::Boolean) }
  def is_dormant_value(val, threshold = GitHub.dormancy_threshold)
    if val.is_a?(Time)
      val < Time.now - threshold
    else
      val.nil? || val == 0 || val == false
    end
  end

  sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def last_billing_transaction_time
    if GitHub.billing_enabled? && (txn = billing_transactions.last)
      txn.created_at
    end
  end

  sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def last_web_session_time
    if session = most_recent_session
      session.accessed_at
    end
  end

  sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def last_repo_star_time
    if last_star = stars.last
      last_star.created_at
    end
  end

  sig { returns(T.nilable(Time)) }
  def last_repo_watch_time
    response = GitHub.newsies.subscriptions(self, set: :all, page: 1, per_page: 1, sort: :desc, list_type: "Repository")
    if response.success?
      subscriptions = response.value
      if subscriptions.present?
        subscriptions.first.created_at
      end
    end
  end

  sig { params(action: T.any(String, Symbol)).returns(T.nilable(Time)) }
  def last_audit_log_entry_time_for_user_by_action(action)
    options = {
      user_id: id,
      allowlist: [action],
      raw: true,
      per_page: 1,
    }
    query = Audit::Driftwood::Query.new_user_query(options)
    execute_driftwood_query_for_created_at(query)
  end

  # note this function is using a special query
  # provided by Driftwood::Query - new_dormant_user_query
  # this calls driftwood_client.dormant_user_query with only the user_id
  # and doesn't pass through all provided options
  sig { returns(T.nilable(Time)) }
  def last_audit_log_entry_time_for_user_dormancy_actions
    options = {
      actor_id: id,
      allowlist: AuditLogEntry.user_dormancy_action_names,
      raw: true,
    }
    query = Audit::Driftwood::Query.new_dormant_user_query(options)
    execute_driftwood_query_for_created_at(query)
  end

  sig { params(query: T.any(Audit::Driftwood::Query, Search::Queries::AuditLogQuery)).returns(T.nilable(Time)) }
  def execute_driftwood_query_for_created_at(query)
    hits = begin
      query.execute
    rescue # rubocop:todo Lint/GenericRescue
      Search::Results.empty
    end

    if hits.any?
      hit = hits.first
      Time.at(hit["created_at"] / 1000)
    end
  end

  sig { returns(String) }
  def signup_timeframe
    created_at = self.created_at
    return "unknown" unless created_at

    if created_at > 1.day.ago
      "onboarding"
    elsif created_at > 30.days.ago
      "recent"
    else
      "established"
    end
  end

  sig { returns(T.nilable(Time)) }
  def last_personal_token_access_time
    oauth_accesses.personal_tokens.order(accessed_at: :desc).pick(:accessed_at)
  end

  sig { returns(T.nilable(Time)) }
  def last_public_key_access_time
    public_keys.order(accessed_at: :desc).pick(:accessed_at)
  end
end
