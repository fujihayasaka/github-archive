# typed: strict
# frozen_string_literal: true

module Organization::DormancyDependency
  extend T::Helpers
  # Org-specific overrides for the active account checks.
  # See app/models/user/dormancy_dependency.rb for more details

  requires_ancestor { Organization }


  sig { params(threshold: ActiveSupport::Duration, strict: T::Boolean).returns(T::Boolean) }
  def exempt_from_dormancy?(threshold = GitHub.dormancy_threshold, strict: false)
    cutoff = Time.now - threshold
    # On Enterprise orgs do not count against the paid seats, so dormancy never
    # needs to be checked for them
    return true if GitHub.enterprise?

    # Paying us earns an exemption
    return true if GitHub.billing_enabled? && plan.paid? && !disabled?

    # If any repos are active (have recent pushes), then the owner user is
    # active too.  We check this to ensure we don't disrupt an active repo that
    # has an otherwise dormant owner.
    #
    # NOTE: Also update `Repository#dormant?` if changing this logic.
    return true if repositories.where(
      "created_at > :cutoff AND pushed_at > :cutoff",
      cutoff: cutoff,
    ).any?

    if strict
      # The organization must have no active team members otherwise it's exempt
      return true if last_active != "No activity" && last_active >= cutoff
      most_recent_admin = admins.order(updated_at: :desc).limit(1).first
      return true if !most_recent_admin.nil? && most_recent_admin.recently_active?
    else
      # Check collaboration (having many members and at least one active repo)
      has_pushed_repo = repositories.any? { |repo| !repo.never_pushed_to? }
      return true if has_pushed_repo && member_count > 1
    end

    false
  end

  sig { params(threshold: ActiveSupport::Duration).returns(T.nilable(T::Boolean)) }
  def recently_active?(threshold = GitHub.dormancy_threshold)
    cutoff = Time.now - threshold

    # Creating an account is activity
    return true if created_at >= cutoff

    # Paying us (or attempting to) is activity
    last_bill = last_billing_transaction_time
    return true if last_bill && last_bill >= cutoff

    # Check for dashboard events, the most fundamental indicator of activity
    last_event = if T.unsafe(self).feature_enabled?(:conduit_user_dormancy)
      last_conduit_event_at
    else
      last_stratocaster_event_at
    end

    return true if last_event && last_event >= cutoff

    # Finally, check the audit log for any non-failure events
    last_audit_event = last_audit_log_entry_time
    true if last_audit_event && last_audit_event >= cutoff
  end

  # Public: Compute whether the organization fulfills strict dormancy guidelines
  sig { params(threshold: ActiveSupport::Duration).returns(T::Hash[Symbol, T.untyped]) }
  def build_dormancy_status(threshold = GitHub.dormancy_threshold)
    dormancy_status = {}

    # Account creation is activity
    dormancy_status[:created_at] = created_at

    # Paying us (or attempting to) is activity
    paid = GitHub.billing_enabled? && plan.paid? && !disabled?
    dormancy_status[:paid] = paid

    dormancy_status[:last_transaction] = last_billing_transaction_time

    # If any repos are active (have recent pushes), then the owner user is
    # active too.  We check this to ensure we don't disrupt an active repo that
    # has an otherwise dormant owner.
    dormancy_status[:active_repo_owner] = repositories.any? { |repo| !repo.dormant?(threshold) }

    # Check for dashboard events, the most fundamental indicator of activity
    dormancy_status[:last_event] = if T.unsafe(self).feature_enabled?(:conduit_user_dormancy)
      last_conduit_event_at
    else
      last_stratocaster_event_at
    end

    # Finally, check the audit log for any non-failure events
    dormancy_status[:last_log] = last_audit_log_entry_time

    # is the owner account active?
    dormancy_status[:last_admin_event] = last_active if last_active != "No activity"
    dormancy_status[:active_admin] = recent_admin&.recently_active? if admins.any?

    dormancy_status[:ignored] = {}

    # information that we want to track but that we shouldn't use to evaluate dormancy
    dormancy_status[:ignored][:org_size] = member_count
    if member_count < 3
      dormancy_status[:ignored][:org_active_members] = members.any? { |user| user.recently_active? }
    end

    # Check collaboration (having many members and at least one active repo)
    has_pushed_repo = repositories.any? { |repo| !repo.never_pushed_to? }
    dormancy_status[:ignored][:org_collaboration] = has_pushed_repo && member_count > 1

    # Track total repository ownership
    dormancy_status[:ignored][:repo_owner_count] = repositories.network_roots.count

    # Set dormant to false if all keys are 0, nil, false, or a time before the cutoff
    dormancy_status[:active_keys] = dormancy_status.filter { |key, value| key != :ignored && !is_dormant_value(value, threshold) }.keys.sort

    if dormancy_status[:active_keys].empty?
      dormancy_status[:dormant] = true
    else
      dormancy_status[:dormant] = false
    end

    dormancy_status
  end

  sig { returns(T.nilable(Time)) }
  def last_audit_log_entry_time
    return nil unless GitHub.enterprise?

    query_params = [
      "(actor_id:#{id} OR (org_id:#{id} AND _exists_:org))",
      "-action:staff.*",
    ]
    options = {
      phrase: query_params.join(" "),
      org: self,
    }
    query = Audit::Driftwood::Query.org_dormancy(options)
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
end
