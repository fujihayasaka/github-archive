# typed: strict
# frozen_string_literal: true

# Diagnostic tool for comparing dotcom's Copilot seat counts to Licensify's
# license counts for a single customer. Not used in application code paths.
#
# Usage (from console):
#
#   biz = Business.find_by_slug("some-customer")
#   v = Copilot::LicensifyValidator.new(biz)
#
#   org = Organization.find_by_login("some-org")
#   v = Copilot::LicensifyValidator.new(org)
#
#   v.to_h          # => summary with counts, match status, warnings
#   v.match?         # => true/false
#   v.user_diff      # => detailed user-level diff (slower, extra API call)
#
class Copilot::LicensifyValidator
  extend T::Helpers
  include Licensing::Licensify
  include GitHub::Memoizer

  sig { params(owner: Copilot::Owner).void }
  def initialize(owner)
    @owner = owner
  end

  sig { returns(T.nilable(Integer)) }
  memoize def customer_id
    Licensing::Customer.id_for(@owner)
  end

  # Per-plan count comparison: four pairs of (dotcom, licensify) values.
  sig { returns(T::Hash[Symbol, T::Hash[Symbol, Integer]]) }
  memoize def counts
    dotcom = dotcom_counts_by_license
    active = T.must(dotcom[:active])
    billable = T.must(dotcom[:billable])

    {
      active_business:     { dotcom: T.must(active[:business]),     licensify: attributer.active_business_count },
      active_enterprise:   { dotcom: T.must(active[:enterprise]),   licensify: attributer.active_enterprise_count },
      billable_business:   { dotcom: T.must(billable[:business]),   licensify: attributer.billable_business_count },
      billable_enterprise: { dotcom: T.must(billable[:enterprise]), licensify: attributer.billable_enterprise_count },
    }
  end

  sig { returns(T::Boolean) }
  def match?
    counts.values.all? { |v| v[:dotcom] == v[:licensify] }
  end

  # Contextual warnings about conditions that cause expected transient mismatches.
  sig { returns(T::Array[String]) }
  memoize def warnings
    result = T.let([], T::Array[String])

    if customer_id.nil?
      result << "No Licensify customer linked to this owner. Licensify counts will be 0."
    end

    recent = seat_assignments_in_cooldown
    if recent.any?
      details = recent.map { |sa| "#{sa.assignable_type} #{sa.assignable_id} (created #{sa.created_at.iso8601})" }
      result << "Seat assignments in cooldown (may cause transient mismatch): #{details.join(", ")}"
    end

    result
  end

  # User-level diff: which users are in one system but not the other,
  # and which users exist in both but have different plan names.
  # Covers both active and billable user sets.
  # Slower than count comparison (extra API calls + user lookups). Call only when needed.
  sig { returns(T::Hash[Symbol, T.untyped]) }
  memoize def user_diff
    active_dotcom = dotcom_active_user_ids
    active_licensify = licensify_active_user_ids

    active_only_dotcom = active_dotcom - active_licensify
    active_only_licensify = active_licensify - active_dotcom
    active_common = active_dotcom & active_licensify

    billable_dotcom = dotcom_billable_user_ids
    billable_licensify = licensify_billable_user_ids

    billable_only_dotcom = billable_dotcom - billable_licensify
    billable_only_licensify = billable_licensify - billable_dotcom
    billable_common = billable_dotcom & billable_licensify

    {
      active: {
        dotcom_count: active_dotcom.size,
        licensify_count: active_licensify.size,
        in_common: active_common.size,
        only_dotcom: resolve_users(active_only_dotcom),
        only_licensify: resolve_users(active_only_licensify, include_suspended: true),
        plan_mismatches: plan_mismatches(active_common, dotcom_active_user_plans, licensify_active_user_plans),
      },
      billable: {
        dotcom_count: billable_dotcom.size,
        licensify_count: billable_licensify.size,
        in_common: billable_common.size,
        only_dotcom: resolve_users(billable_only_dotcom),
        only_licensify: resolve_users(billable_only_licensify, include_suspended: true),
        plan_mismatches: plan_mismatches(billable_common, dotcom_billable_user_plans, licensify_billable_user_plans),
      },
    }
  end

  # Everything in one hash, suitable for serialization or logging.
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_h
    {
      customer_id: customer_id,
      owner_id: @owner.id,
      owner_type: @owner.class.name,
      owner_name: owner_name,
      counts: counts,
      match: match?,
      warnings: warnings,
    }
  end

  private

  sig { returns(String) }
  def owner_name
    case @owner
    when Business then @owner.slug
    when Organization then @owner.display_login
    else T.absurd(@owner)
    end
  end

  sig { returns(Copilot::LicenseAttributer) }
  memoize def attributer
    Copilot::LicenseAttributer.new(@owner)
  end

  # Dotcom seat counts bucketed by plan. Business path delegates to
  # Copilot::Business; Organization path counts seats by SKU directly.
  sig { returns(T::Hash[Symbol, T::Hash[Symbol, Integer]]) }
  memoize def dotcom_counts_by_license
    case @owner
    when Business
      cb = Copilot::Business.new(@owner)
      billable = cb.copilot_enabled_members_count_by_license
      consumed = cb.copilot_enabled_members_count_by_license(consumed_only: true)
      {
        billable: { business: billable[:business].to_i, enterprise: billable[:enterprise].to_i },
        active:   { business: consumed[:business].to_i, enterprise: consumed[:enterprise].to_i },
      }
    when Organization
      org_counts_by_license
    else
      T.absurd(@owner)
    end
  end

  sig { returns(T::Hash[Symbol, T::Hash[Symbol, Integer]]) }
  def org_counts_by_license
    seats = Copilot::Seat
      .for_organization(@owner)
      .joins(:seat_assignment)
      .includes(:seat_assignment)

    active_seats = seats.where(copilot_seat_assignments: { access_revoked_at: nil })
    all_seats = seats.where(
      "copilot_seat_assignments.access_revoked_at IS NULL OR copilot_seat_assignments.pending_cancellation_date IS NOT NULL"
    )

    {
      active:   bucket_seats_by_plan(active_seats),
      billable: bucket_seats_by_plan(all_seats),
    }
  end

  ENTERPRISE_SKUS = T.let(%i[
    COPILOT_ENTERPRISE_SEAT
  ].to_set.freeze, T::Set[Symbol])

  BUSINESS_SKUS = T.let(%i[
    COPILOT_FOR_BUSINESS_SEAT
    COPILOT_FOR_BUSINESS_TRIAL_SEAT
    COPILOT_ENTERPRISE_TRIAL_SEAT
    COPILOT_ENTERPRISE_TRIAL_SEAT_STAFF
  ].to_set.freeze, T::Set[Symbol])

  sig { params(seats: T.untyped).returns(T::Hash[Symbol, Integer]) }
  def bucket_seats_by_plan(seats)
    result = { business: 0, enterprise: 0 }
    seen = T.let(Set.new, T::Set[Integer])

    seats.each do |seat|
      uid = seat.assigned_user_id
      next unless uid
      next if seen.include?(uid)
      seen.add(uid)

      sku = seat.copilot_sku
      if ENTERPRISE_SKUS.include?(sku)
        result[:enterprise] += 1
      elsif BUSINESS_SKUS.include?(sku)
        result[:business] += 1
      end
    end

    result
  end

  sig { returns(T::Set[Integer]) }
  memoize def dotcom_active_user_ids
    seat_scope = case @owner
    when Business
      Copilot::Seat.all_active_seats_in_business(@owner)
    when Organization
      Copilot::Seat.for_organization(@owner).joins(:seat_assignment)
        .where(copilot_seat_assignments: { access_revoked_at: nil })
    else
      T.absurd(@owner)
    end

    seat_scope
      .pluck(:assigned_user_id)
      .compact
      .map(&:to_i)
      .to_set
  end

  # Billable users in dotcom: mirrors copilot_enabled_members_count_by_license(consumed_only: false).
  # For Business: all org seats + enterprise-owned seats (via business_owned). No
  #   access_revoked_at filter — intentionally matches the canonical billable count,
  #   which includes revoked seats because cross-org deduplication happens at a higher level.
  # For Organization: active + pending-cancellation seats (matching org_counts_by_license billable scope).
  sig { returns(T::Set[Integer]) }
  memoize def dotcom_billable_user_ids
    case @owner
    when Business
      org_ids = Copilot::Seat
        .joins(:seat_assignment)
        .where(organization_id: @owner.organization_ids)
        .pluck(:assigned_user_id)
      enterprise_ids = Copilot::Seat
        .business_owned(@owner)
        .pluck(:assigned_user_id)
      (org_ids + enterprise_ids).compact.map(&:to_i).to_set
    when Organization
      Copilot::Seat
        .for_organization(@owner)
        .joins(:seat_assignment)
        .where(
          "copilot_seat_assignments.access_revoked_at IS NULL OR copilot_seat_assignments.pending_cancellation_date IS NOT NULL"
        )
        .pluck(:assigned_user_id)
        .compact
        .map(&:to_i)
        .to_set
    else
      T.absurd(@owner)
    end
  end

  sig { returns(T::Set[Integer]) }
  memoize def licensify_active_user_ids
    licensify_licenses_data[:active_ids]
  end

  sig { returns(T::Set[Integer]) }
  memoize def licensify_billable_user_ids
    licensify_licenses_data[:billable_ids]
  end

  sig { params(user_ids: T::Set[Integer], include_suspended: T::Boolean).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def resolve_users(user_ids, include_suspended: false)
    return [] if user_ids.empty?

    User.where(id: user_ids.to_a).map do |user|
      entry = T.let({ id: user.id, login: user.display_login }, T::Hash[Symbol, T.untyped])
      entry[:suspended] = user.suspended? if include_suspended
      entry
    end
  end

  # Compare plan names for users present in both systems.
  sig { params(common_ids: T::Set[Integer], dotcom_plans: T::Hash[Integer, String], licensify_plans: T::Hash[Integer, String]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def plan_mismatches(common_ids, dotcom_plans, licensify_plans)
    return [] if common_ids.empty?

    mismatched = common_ids.select do |uid|
      d = dotcom_plans[uid]
      l = licensify_plans[uid]
      d && l && d != l
    end

    users_by_id = User.where(id: mismatched.to_a).index_by(&:id)

    mismatched.map do |uid|
      user = users_by_id[uid]
      {
        id: uid,
        login: user&.display_login || "(unknown)",
        dotcom_plan: dotcom_plans[uid],
        licensify_plan: licensify_plans[uid],
      }
    end
  end

  # Map user_id → plan name ("business" or "enterprise") from dotcom seats.
  # Uses the same ENTERPRISE_SKUS/BUSINESS_SKUS bucketing as counts so that
  # plan_mismatches explains exactly which users cause count discrepancies.
  sig { returns(T::Hash[Integer, String]) }
  memoize def dotcom_active_user_plans
    seat_scope = case @owner
    when Business
      Copilot::Seat.all_active_seats_in_business(@owner)
    when Organization
      Copilot::Seat.for_organization(@owner).joins(:seat_assignment)
        .where(copilot_seat_assignments: { access_revoked_at: nil })
    else
      T.absurd(@owner)
    end

    plans = T.let({}, T::Hash[Integer, String])
    seat_scope.includes(:seat_assignment).each do |seat|
      uid = seat.assigned_user_id
      next unless uid

      user_id = uid.to_i
      next if plans.key?(user_id)

      sku = seat.copilot_sku
      if ENTERPRISE_SKUS.include?(sku)
        plans[user_id] = "enterprise"
      elsif BUSINESS_SKUS.include?(sku)
        plans[user_id] = "business"
      end
    end
    plans
  end

  # Like dotcom_active_user_plans but uses billable seat scopes (matches dotcom_billable_user_ids).
  # Business path iterates org seats then enterprise-owned seats separately to
  # avoid a UNION ALL subquery that breaks ActiveRecord eager-loading.
  sig { returns(T::Hash[Integer, String]) }
  memoize def dotcom_billable_user_plans
    seat_scopes = case @owner
    when Business
      [
        Copilot::Seat.joins(:seat_assignment)
          .where(organization_id: @owner.organization_ids),
        Copilot::Seat.business_owned(@owner),
      ]
    when Organization
      [
        Copilot::Seat.for_organization(@owner).joins(:seat_assignment)
          .where(
            "copilot_seat_assignments.access_revoked_at IS NULL OR copilot_seat_assignments.pending_cancellation_date IS NOT NULL"
          ),
      ]
    else
      T.absurd(@owner)
    end

    plans = T.let({}, T::Hash[Integer, String])
    seat_scopes.each do |scope|
      scope.includes(:seat_assignment).each do |seat|
        uid = seat.assigned_user_id
        next unless uid

        user_id = uid.to_i
        next if plans.key?(user_id)

        sku = seat.copilot_sku
        if ENTERPRISE_SKUS.include?(sku)
          plans[user_id] = "enterprise"
        elsif BUSINESS_SKUS.include?(sku)
          plans[user_id] = "business"
        end
      end
    end
    plans
  end

  # Map user_id → current plan name from Licensify customer licenses.
  # Uses the live paidPlan/trialPlan from enablement details.
  sig { returns(T::Hash[Integer, String]) }
  memoize def licensify_active_user_plans
    licensify_licenses_data[:active_plans]
  end

  # Map user_id → billable plan name from Licensify customer licenses.
  # Emulates Licensify's copilotBillableGroupedPlan logic: when a paid enablement
  # was removed this billing period, the billable plan is the higher of the live
  # paid plan and the last paid plan (billing carryover).
  sig { returns(T::Hash[Integer, String]) }
  memoize def licensify_billable_user_plans
    licensify_licenses_data[:billable_plans]
  end

  # Single paginated pass over get_customer_licenses that collects
  # active/billable user IDs and plan mappings for both sections of user_diff.
  sig { returns(T::Hash[Symbol, T.untyped]) }
  memoize def licensify_licenses_data
    active_ids = T.let(Set.new, T::Set[Integer])
    billable_ids = T.let(Set.new, T::Set[Integer])
    active_plans = T.let({}, T::Hash[Integer, String])
    billable_plans = T.let({}, T::Hash[Integer, String])
    return { active_ids: active_ids, billable_ids: billable_ids, active_plans: active_plans, billable_plans: billable_plans } if customer_id.nil?

    start_of_month = Time.now.utc.beginning_of_month

    page_size = Licensing::Licensify::DEFAULT_CUSTOMER_LICENSES_PAGE_SIZE
    offset = 0

    loop do
      response = get_customer_licenses(
        T.must(customer_id),
        product: Licensing::Licensify::LicensifyProduct::COPILOT,
        limit: page_size,
        offset: offset,
      )

      licenses = response.customerLicenses.to_a
      licenses.each do |license|
        licensee = license.licensee
        next unless licensee

        uid = licensee.id.to_i
        next if uid == 0

        billable_ids.add(uid)
        is_active = license.licenseStatus == :LICENSE_STATUS_ACTIVE
        active_ids.add(uid) if is_active

        if is_active
          detail = license.enablementDetails.to_a.first
          plan = detail&.paidPlan.presence || detail&.trialPlan.presence
          active_plans[uid] = plan if plan
        end

        billable_plan = licensify_billable_plan_for(license, start_of_month)
        billable_plans[uid] = billable_plan if billable_plan
      end

      break if licenses.empty? || (offset + page_size) >= response.total
      offset += page_size
    end

    { active_ids: active_ids, billable_ids: billable_ids, active_plans: active_plans, billable_plans: billable_plans }
  end

  VALID_LICENSIFY_PLANS = T.let(%w[business enterprise].to_set.freeze, T::Set[String])

  # Emulates Licensify's copilotBillableGroupedPlan logic for a single license.
  # Enterprise wins over Business when resolving multiple plans.
  sig { params(license: T.untyped, start_of_month: Time).returns(T.nilable(String)) }
  def licensify_billable_plan_for(license, start_of_month)
    details = license.enablementDetails.to_a
    paid_plans = details.filter_map { |d| d.paidPlan.presence }.select { |p| VALID_LICENSIFY_PLANS.include?(p) }
    live_paid_plan = resolve_licensify_plan(paid_plans)

    last_paid = license.lastPaidPlan.presence
    last_paid_plan = last_paid && VALID_LICENSIFY_PLANS.include?(last_paid) ? last_paid : nil

    removed_at = license.paidEnablementRemovedAt
    removed_this_period = removed_at && removed_at.to_time >= start_of_month

    if removed_this_period
      return resolve_licensify_plan([live_paid_plan, last_paid_plan].compact)
    end

    return live_paid_plan if live_paid_plan

    # No live paid plan — fall back to trial plan, then last paid plan.
    trial_plans = details.filter_map { |d| d.trialPlan.presence }.select { |p| VALID_LICENSIFY_PLANS.include?(p) }
    trial_plan = resolve_licensify_plan(trial_plans)
    return last_paid_plan if trial_plan.nil?

    trial_plan
  end

  # Enterprise wins over Business, matching Licensify's ResolveEffectivePlanName.
  sig { params(plans: T::Array[String]).returns(T.nilable(String)) }
  def resolve_licensify_plan(plans)
    return "enterprise" if plans.include?("enterprise")
    return "business" if plans.include?("business")

    nil
  end

  MAX_COOLDOWN = T.let(
    Copilot::COPILOT_SEAT_COOLDOWN_PERIODS.values.max || 0.seconds,
    ActiveSupport::Duration,
  )

  # Maps the assignable_type column string to the cooldown key symbol
  # without loading the polymorphic assignable record.
  ASSIGNABLE_TYPE_TO_COOLDOWN_KEY = T.let({
    "User" => :USER,
    "Team" => :TEAM,
    "BusinessTeam" => :BUSINESS_TEAM,
    "EnterpriseTeam" => :ENTERPRISE_TEAM,
    "Organization" => :ORGANIZATION,
  }.freeze, T::Hash[String, Symbol])

  sig { returns(T::Array[Copilot::SeatAssignment]) }
  memoize def seat_assignments_in_cooldown
    owner_seat_assignments
      .where("created_at > ?", MAX_COOLDOWN.ago)
      .to_a
      .select { |sa| cooldown_active?(sa) }
  end

  # Side-effect-free cooldown check that avoids both the dogstats/logging
  # in SeatAssignment#in_cooldown_period? and the N+1 from loading assignable.
  sig { params(sa: Copilot::SeatAssignment).returns(T::Boolean) }
  def cooldown_active?(sa)
    key = ASSIGNABLE_TYPE_TO_COOLDOWN_KEY[sa.assignable_type]
    return false unless key

    duration = Copilot::COPILOT_SEAT_COOLDOWN_PERIODS[key]
    return false unless duration

    sa.created_at > duration.ago
  end

  sig { returns(T.untyped) }
  def owner_seat_assignments
    case @owner
    when Business
      Copilot::SeatAssignment.where(owner: @owner)
        .or(Copilot::SeatAssignment.where(owner_type: "Organization", owner_id: @owner.organization_ids))
    when Organization
      Copilot::SeatAssignment.where(owner_type: "Organization", owner_id: @owner.id)
    else
      T.absurd(@owner)
    end
  end
end
