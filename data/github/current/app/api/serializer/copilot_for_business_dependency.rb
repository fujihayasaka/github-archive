# typed: true
# frozen_string_literal: true

module Api::Serializer::CopilotForBusinessDependency
  include Api::Serializer::EnterpriseTeamsDependency
  include Api::Serializer::OrganizationsDependency
  include Api::Serializer::UserDependency
  include GitHub::Memoizer

  def copilot_seat_detail_hash(data, options = {})
    assignee = data[:assignee]
    seat = data[:seat]
    seat_assignment = seat.seat_assignment
    usage_detail = data[:usage_detail]
    enterprise = data[:enterprise]
    return_real_creation_date = data[:return_real_creation_date]
    plan_type = data.fetch(:plan_type, "unknown")

    assignable_type = seat_assignment&.symbolized_assignable_type
    assignee_hash = simple_user_hash(assignee, options)

    if return_real_creation_date
      seat_created_at = seat.created_at
      seat_updated_at = seat.updated_at
    else
      seat_created_at = seat_assignment.present? ? [seat.created_at, seat_assignment.created_at].min : seat.created_at
      seat_updated_at = seat_assignment.present? ? [seat.updated_at, seat_assignment.updated_at].max : seat.updated_at
    end

    hash = {
      created_at: seat_created_at&.iso8601,
      assignee: assignee_hash,
      updated_at: seat_updated_at&.iso8601,
      pending_cancellation_date: seat_assignment&.pending_cancellation_date&.iso8601,
      plan_type: plan_type
    }

    usage_details_hash = {
      last_activity_at: usage_detail&.updated_at&.iso8601,
      last_activity_editor: usage_detail&.editor_details,
    }
    hash.merge!(usage_details_hash)

    # Include the assigning team if we're getting a user's seat detail and they were assigned via a team
    if assignable_type == :TEAM
      assigning_team = team_hash(seat_assignment.assignable, options)
      hash.update(assigning_team: assigning_team)
    elsif assignable_type == :ENTERPRISE_TEAM
      assigning_enterprise_team = enterprise_team_hash(seat_assignment.assignable, options)
      hash.update(assigning_team: assigning_enterprise_team)
    end

    if enterprise && seat.organization
      hash[:organization] = organization_hash(seat.organization, options)
    end

    hash
  end

  def total_seats_hash(data, options = {})
    seats_key = options[:created] ? :seats_created : :seats_cancelled
    {
      seats_key => data[:seat_count]
    }
  end

  def copilot_org_summary_hash(data, options = {})
    org = data[:org]
    copilot_org = Copilot::Organization.new(org)

    seat_management_setting = if copilot_org.seat_management_enabled_for_all?
      "assign_all"
    elsif copilot_org.seat_management_enabled_for_selected?
      "assign_selected"
    elsif copilot_org.seat_management_unconfigured?
      "unconfigured"
    else
      "disabled"
    end

    public_code_suggestions_policy = if !copilot_org.public_code_suggestions_configured?
      "unconfigured"
    elsif copilot_org.allow_public_code_suggestions?
      "allow"
    elsif copilot_org.block_public_code_suggestions?
      "block"
    else
      "unknown"
    end

    platform_chat_policy = if !copilot_org.dotcom_chat_configured?
      "unconfigured"
    elsif copilot_org.dotcom_chat_enabled?
      "enabled"
    elsif copilot_org.dotcom_chat_disabled?
      "disabled"
    else
      "unknown"
    end

    cli_policy = if !copilot_org.cli_configured?
      "unconfigured"
    elsif copilot_org.cli_enabled?
      "enabled"
    elsif copilot_org.cli_disabled?
      "disabled"
    else
      "unknown"
    end

    hash = {
      seat_breakdown: copilot_seat_breakdown(org, copilot_org),
      seat_management_setting: seat_management_setting,
      public_code_suggestions: public_code_suggestions_policy,
      ide_chat: copilot_org.chat_setting,
      cli: cli_policy,
      plan_type: copilot_org.copilot_plan
    }

    if org.business && Copilot::Business.new(org.business).has_copilot_enterprise_access?
      hash[:platform_chat] = platform_chat_policy
    end

    hash
  end

  def copilot_seat_breakdown(org, copilot_org)
    cycle_start = org.current_metered_billing_cycle_starts_at
    seats_for_org = Copilot::Seat.for_organization(org)

    total_seats = seats_for_org.count
    seats_pending_cancellation = seats_for_org.joins(:seat_assignment).where.not(seat_assignment: { pending_cancellation_date: nil }).count

    seat_history_for_org = Copilot::SeatHistory.where(organization: org)
    seats_added_this_cycle = seat_history_for_org.where("seat_created_at >= ?", cycle_start).count

    seats_active_this_cycle = Copilot::AggregateUsageDetail.joins("INNER JOIN copilot_seats ON copilot_aggregate_usage_details.user_id = copilot_seats.assigned_user_id")
      .where("copilot_aggregate_usage_details.updated_at >= ?", cycle_start)
      .where("copilot_seats.organization_id = ?", org.id)
      .select(:user_id).distinct.count

    {
      total: total_seats,
      added_this_cycle: seats_added_this_cycle,
      pending_invitation: Copilot::SeatAssignment.where(organization_id: org.id, assignable_type: "OrganizationInvitation").count,
      pending_cancellation: seats_pending_cancellation,
      active_this_cycle: seats_active_this_cycle,
      inactive_this_cycle: total_seats - seats_active_this_cycle
    }
  end

  def copilot_seats_list_hash(data, options = {})
    seat_count = data[:count]
    seats = data[:seats]
    enterprise = data.fetch(:enterprise, false)
    real_creation_date = data[:return_real_creation_date]
    plan_types = data[:plan_types]

    hash = { total_seats: seat_count, seats: [] }

    seats.each do |seat|
      # usage detail will be nil unless the assignee already has a seat
      usage_detail = Copilot::AggregateUsageDetail.latest_for_users(seat.assigned_user)
      hash[:seats].append(
        copilot_seat_detail_hash({
          assignee: seat.assigned_user,
          seat: seat,
          usage_detail: usage_detail,
          enterprise: enterprise,
          return_real_creation_date: real_creation_date,
          plan_type: plan_types.dig(seat.copilot_seat_assignment_id, :plan) || "unknown"
        },
        options)
      )
    end
    hash
  end
end
