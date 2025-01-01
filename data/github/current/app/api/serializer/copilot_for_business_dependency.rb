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
    plan_type = data.fetch(:plan_type, "unknown")

    assignable_type = seat_assignment&.symbolized_assignable_type
    assignee_hash = simple_user_hash(assignee, options)

    seat_created_at = seat.created_at
    seat_updated_at = seat.updated_at

    hash = {
      created_at: seat_created_at&.iso8601,
      assignee: assignee_hash,
      pending_cancellation_date: seat_assignment&.pending_cancellation_date&.iso8601,
      plan_type: plan_type
    }

    unless Api::SerializerOptions.from(options).changeset_active?(:remove_copilot_seat_detail_updated_at)
      hash[:updated_at] = seat_updated_at&.iso8601
    end

    hash.merge!(get_usage_details_hash(usage_detail))

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

  def copilot_entity_summary_hash(data, options = {})
    entity = data[:entity]
    copilot_entity = T.let(
      T.must(case entity
      when ::Organization
        Copilot::Organization.new(entity)
      when ::Business
        Copilot::Business.new(entity)
      end),
      T.any(Copilot::Organization, Copilot::Business)
    )

    details_hash = {
      seat_breakdown: copilot_seat_breakdown(entity, copilot_entity),
    }

    if entity.is_a?(::Organization)
      details_hash[:seat_management_setting] = get_seat_management_setting_for_org(copilot_entity)

      # TODO: we will want to get this for Businesses as well once it's toggle-able at that level
      details_hash[:plan_type] = copilot_entity.copilot_plan
    else
      details_hash[:copilot_enablement] = T.cast(copilot_entity, Copilot::Business).copilot_business_enablement_setting
    end

    policies = get_policies_for_entity(copilot_entity, entity.feature_enabled?(:copilot_expanded_policies_in_details_api))

    details_hash.merge!(policies)
  end

  def copilot_seats_list_hash(data, options = {})
    seat_count = data[:count]
    seats = data[:seats]
    enterprise = data.fetch(:enterprise, false)
    plan_types = data[:plan_types]

    hash = { total_seats: seat_count, seats: [] }

    seats.each do |seat|
      # usage detail will be nil unless the assignee already has a seat
      usage_detail = copilot_activity_api_enabled?(seat) ? Copilot::Activity.for_seat(seat) : Copilot::AggregateUsageDetail.latest_for_users(seat.assigned_user)
      hash[:seats].append(
        copilot_seat_detail_hash({
          assignee: seat.assigned_user,
          seat: seat,
          usage_detail: usage_detail,
          enterprise: enterprise,
          plan_type: plan_types.dig(seat.copilot_seat_assignment_id, :plan) || "unknown"
        },
        options)
      )
    end
    hash
  end

  private

  def copilot_activity_api_enabled?(seat)
    # check the user first as it's faster
    return true if seat.assigned_user.feature_enabled?(:copilot_activity_api)
    # see if they have a seat assignment
    return false if seat.seat_assignment.nil?
    # check the owner
    seat.owner.feature_enabled?(:copilot_activity_api)
  end

  def get_usage_details_hash(usage_detail)
    # if we don't have a usage detail, we don't need to return anything
    return {} unless usage_detail

    return {
      last_activity_at: usage_detail.updated_at.iso8601,
      last_activity_editor: usage_detail.editor_details,
    } if usage_detail.is_a?(Copilot::AggregateUsageDetail)

    return {
      last_activity_at: usage_detail.activity_at.iso8601,
      last_activity_editor: usage_detail.activity_details,
    } if usage_detail.is_a?(Copilot::Activity)

    GitHub.logger.warn("Unknown usage detail type: #{usage_detail.class}")
    {}
  end

  def get_seat_management_setting_for_org(copilot_entity)
    if copilot_entity.seat_management_enabled_for_all?
      "assign_all"
    elsif copilot_entity.seat_management_enabled_for_selected?
      "assign_selected"
    elsif copilot_entity.seat_management_unconfigured?
      "unconfigured"
    else
      "disabled"
    end
  end

  def copilot_seat_breakdown(entity, copilot_entity)
    cycle_start = entity.current_metered_billing_cycle_starts_at
    cycle_end = entity.next_metered_billing_cycle_starts_at

    is_standalone = copilot_entity.copilot_standalone?

    if entity.is_a?(::Organization)
      owner_ids = [entity.id]
      assignments_for_entity = Copilot::SeatAssignment.where(owner_type: "Organization", owner_id: owner_ids)

      # this uses the organization column on copilot_seats, which is indexed; so it's faster than doing for_owner
      seats_for_entity = Copilot::Seat.for_organization(entity)
    elsif entity.is_a?(::Business)
      owner_ids = is_standalone ? [entity.id] : entity.organization_ids
      assignment_owner_type = is_standalone ? "Business" : "Organization"

      assignments_for_entity = Copilot::SeatAssignment.where(
        owner_type: assignment_owner_type,
        owner_id: owner_ids
      )
      seats_for_entity = is_standalone ? Copilot::Seat.for_standalone_business(entity) : Copilot::Seat.where(organization_id: owner_ids)
    end

    seats_pending_cancellation = T.must(assignments_for_entity).where.not(pending_cancellation_date: nil).count
    pending_invitation = T.must(assignments_for_entity).where(assignable_type: "OrganizationInvitation").count

    hash = {
      pending_invitation: pending_invitation,
      pending_cancellation: seats_pending_cancellation,
    }

    unless is_standalone
      # TODO: Copilot::SeatHistory.where(owner_id: entity.id) is too slow for standalones; add back in once there's an index on owner_id on seat_histories
      seat_history_for_entity = Copilot::SeatHistory.where(organization_id: owner_ids, billing_cycle_start_date: cycle_start, billing_cycle_end_date: cycle_end)
      seats_added_this_cycle = seat_history_for_entity.where("seat_created_at >= ?", cycle_start).count
      hash[:added_this_cycle] = seats_added_this_cycle
    end

    total_seats = T.must(seats_for_entity).count
    total_unique_seats = T.must(seats_for_entity).pluck(:assigned_user_id).uniq.size

    if entity.is_a?(::Business)
      # This is deduplicated by assigned_user_id, so that we don't double-count seats billed when a user
      # is a member of multiple organizations in the enterprise
      hash[:total_seats_billed] = total_unique_seats
    else
      # TODO: for GA let's rename this to total_seats_billed for organizations
      hash[:total] = total_seats

      # we might eventually add this for enterprises, but there are issues with AggregateUsageDetails that we are working out.
      seats_active_this_cycle = Copilot::AggregateUsageDetail
      .joins("INNER JOIN copilot_seats ON copilot_aggregate_usage_details.user_id = copilot_seats.assigned_user_id")
      .where("copilot_aggregate_usage_details.updated_at >= ?", cycle_start)
      .where("copilot_seats.organization_id = ?", entity.id)
      .select(:user_id).distinct.count

      hash[:active_this_cycle] = seats_active_this_cycle
      hash[:inactive_this_cycle] = total_unique_seats - seats_active_this_cycle
    end

    hash
  end

  def get_policies_for_entity(copilot_entity, include_expanded_policies = false)
    public_code_suggestions_policy = if !copilot_entity.public_code_suggestions_configured?
      "unconfigured"
    elsif copilot_entity.allow_public_code_suggestions?
      "allow"
    elsif copilot_entity.block_public_code_suggestions?
      "block"
    elsif copilot_entity.is_a?(Copilot::Business) && copilot_entity.snippy_setting == "no_policy"
      "no_policy"
    else
      "unknown"
    end


    policies = {
      public_code_suggestions: public_code_suggestions_policy,
      ide_chat: copilot_entity.chat_setting,
      cli: copilot_entity.cli_setting,
      platform_chat: copilot_entity.dotcom_chat_setting,
    }

    if include_expanded_policies
      mobile_chat_policy = if copilot_entity.is_a?(Copilot::Business)
        copilot_entity.mobile_chat_setting
      else
        copilot_entity.mobile_chat_enabled? ? "enabled" : "disabled"
      end

      metrics_api_policy = if copilot_entity.is_a?(Copilot::Business)
        copilot_entity.usage_telemetry_api_setting
      else
        copilot_entity.telemetry_aggregation_enabled? ? "enabled" : "disabled"
      end

      bing_policy = if copilot_entity.is_a?(Copilot::Business)
        copilot_entity.bing_github_chat_setting
      else
        copilot_entity.bing_github_chat_enabled? ? "enabled" : "disabled"
      end

      policies[:mobile_chat] = mobile_chat_policy
      policies[:metrics_api] = metrics_api_policy
      policies[:anthropic_claude] = copilot_entity.a_chat_setting
      policies[:google_gemini] = copilot_entity.g_chat_setting
      policies[:openai_o1] = copilot_entity.o1_setting
      policies[:bing_access] = bing_policy
      # excluding standalones because as of this writing the extensions policy does not exist for them
      policies[:extensions] = copilot_entity.copilot_extensions_setting unless copilot_entity.copilot_standalone?
    end

    policies
  end
end
