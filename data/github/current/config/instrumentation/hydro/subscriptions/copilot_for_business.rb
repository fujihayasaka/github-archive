# typed: strict
# frozen_string_literal: true

# These are GlobalInstrumenter subscriptions that emit Hydro events related to GitHub Copilot.
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  # This is triggered when a user emits a telemetry snapshot
  subscribe(::Copilot::Events::TELEMETRY_SNAPSHOT) do |payload|
    telemetry_snapshot = payload.fetch(:telemetry_snapshot, nil)

    if telemetry_snapshot.present?
      message = {
        businesses: telemetry_snapshot.businesses.map { |business| serializer.business(business) },
        copilot_access_type: telemetry_snapshot.access_type,
        copilot_telemetry_snapshot_id: telemetry_snapshot.telemetry_snapshot_id,
        copilot_telemetry_snapshot_metadata: serializer.copilot_for_business_details(telemetry_snapshot.telemetry_snapshot_metadata),
        enterprise_team_ids: telemetry_snapshot.enterprise_team_ids,
        organizations: telemetry_snapshot.organizations.map { |org| serializer.copilot_organization(org) },
        source: telemetry_snapshot.source,
        teams: telemetry_snapshot.teams.map { |team| serializer.team(team) },
        user: serializer.user(telemetry_snapshot.copilot_user),
      }

      publish(message, schema: "github.copilot.v2.CopilotTelemetrySnapshot")
    end
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_CLICKWRAP_SAVED) do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      business: serializer.business(payload[:business]),
      actor: serializer.user(payload[:actor]),
    }

    publish(message, schema: "github.copilot.v2.CopilotClickwrapSavedEvent")
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_CLICKWRAP_SHOWN) do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      business: serializer.business(payload[:business]),
      actor: serializer.user(payload[:actor]),
    }

    publish(message, schema: "github.copilot.v2.CopilotClickwrapShownEvent")
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_ENTERPRISE_SETTINGS_CHANGED) do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      business: serializer.business(payload[:business]),
      old_settings: serializer.copilot_business_settings(payload[:old_settings]),
      new_settings: serializer.copilot_business_settings(payload[:new_settings]),
    }

    Copilot::BatchUpdateEnterpriseUserSettingsJob.perform_later(payload[:business])

    publish(message, schema: "github.copilot.v2.CopilotForBusinessEnterpriseSettingsChanged")
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_INDIVIDUAL_SEAT_CONVERTED) do |payload|
    copilot_user = Copilot::User.new(payload[:user])
    other_cfb_org_tracking_ids = copilot_user.orgs_having_copilot_for_business.collect(&:analytics_tracking_id).to_s
    seat = payload[:seat]

    message = {
      copilot_for_business_details: serializer.copilot_for_business_details(payload[:details]),
      other_cfb_organization_analytics_tracking_ids: other_cfb_org_tracking_ids,
      owner_details: serializer.copilot_owner_details(seat.seat_assignment&.owner),
      seat: serializer.copilot_seat(seat),
      subscription_duration: payload[:subscription_item_duration],
      subscription_item_id: payload[:subscription_item_id],
      user: serializer.user(payload[:user]),
    }

    publish(message, schema: "github.copilot.v2.CopilotForBusinessIndividualSeatConverted")
    copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
    if FeatureFlag.vexi.enabled?(:copilot_instrument_copilot_license_or_billable_customer_change, copilot_user.user_object, default: false)
      Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(Copilot::Public::User.new(copilot_user.user_object))
    end
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_ORG_SETTINGS_CHANGED) do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      owner_details: serializer.copilot_owner_details(payload[:organization]),
      old_settings_value: serializer.copilot_organization_settings(payload[:old_settings]),
      new_settings_value: serializer.copilot_organization_settings(payload[:new_settings]),
    }

    publish(message, schema: "github.copilot.v2.CopilotForBusinessOrganizationSettingsChanged")

    Copilot::BatchUpdateUserSettingsJob.perform_later(payload[:organization]&.id)
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_ADDED) do |payload|
    copilot_user = Copilot::User.new(payload[:user])
    other_cfb_org_tracking_ids = copilot_user.orgs_having_copilot_for_business.collect(&:analytics_tracking_id).to_s
    message = {
      actor: serializer.user(payload[:actor]),
      copilot_for_business_details: serializer.copilot_for_business_details(payload[:details]),
      event_type: payload[:event_type].to_s,
      owner_details: serializer.copilot_owner_details(payload[:owner]),
      other_cfb_organization_analytics_tracking_ids: other_cfb_org_tracking_ids,
      seat: serializer.copilot_seat(payload[:seat]),
      user: serializer.user(payload[:user]),
    }

    publish(message, schema: "github.copilot.v2.CopilotForBusinessSeatAdded")
    copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
    if FeatureFlag.vexi.enabled?(:copilot_instrument_copilot_license_or_billable_customer_change, copilot_user.user_object, default: false)
      Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(Copilot::Public::User.new(copilot_user.user_object))
    end
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT_CONVERSION) do |payload|
    seat_assignment = payload[:seat_assignment]

    message = {
      assignment: serializer.copilot_seat_assignment(seat_assignment),
      owner_details: serializer.copilot_owner_details(payload[:owner]),
      existing_seats_count: payload[:existing_seats_count],
      matched_existing_seat_count: payload[:matched_existing_seat_count],
      seat_to_insert_count: payload[:seat_to_insert_count],
    }

    publish(message, schema: "github.copilot.v2.CopilotForBusinessSeatAssignmentConversion")
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT_CREATED) do |payload|
    message = {
      assignment: serializer.copilot_seat_assignment(payload[:assignment]),
      owner_details: serializer.copilot_owner_details(payload[:owner]),
      actor: serializer.user(payload[:actor]),
      event_type: payload[:event_type].to_s,
      copilot_for_business_details: serializer.copilot_for_business_details(payload[:details]),
    }

    publish(message, schema: "github.copilot.v2.CopilotForBusinessSeatAssignmentCreated")
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT_REFRESHED) do |payload|
    message = {
      assignment: serializer.copilot_seat_assignment(payload[:assignment]),
      owner_details: serializer.copilot_owner_details(payload[:owner]),
      actor: serializer.user(payload[:actor]),
      event_type: payload[:event_type].to_s,
      copilot_for_business_details: serializer.copilot_for_business_details(payload[:details]),
    }

    publish(message, schema: "github.copilot.v2.CopilotForBusinessSeatAssignmentRefreshed")
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT_REUSED) do |payload|
    message = {
      assignment: serializer.copilot_seat_assignment(payload[:assignment]),
      owner_details: serializer.copilot_owner_details(payload[:owner]),
      actor: serializer.user(payload[:actor]),
      event_type: payload[:event_type].to_s,
      copilot_for_business_details: serializer.copilot_for_business_details(payload[:details]),
    }

    publish(message, schema: "github.copilot.v2.CopilotForBusinessSeatAssignmentReused")
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT_UNASSIGNED) do |payload|
    message = {
      assignment: serializer.copilot_seat_assignment(payload[:assignment]),
      owner_details: serializer.copilot_owner_details(payload[:owner]),
      actor: serializer.user(payload[:actor]),
      event_type: payload[:event_type].to_s,
      pending_cancellation_date: payload[:pending_cancellation_date],
      copilot_for_business_details: serializer.copilot_for_business_details(payload[:details]),
    }

    publish(message, schema: "github.copilot.v2.CopilotForBusinessSeatAssignmentUnassigned")
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_CANCELLED) do |payload|
    copilot_user = Copilot::User.new(payload[:user])
    other_cfb_organization_analytics_tracking_ids = copilot_user.orgs_having_copilot_for_business.collect(&:analytics_tracking_id).to_s

    message = {
      user: serializer.user(payload[:user]),
      owner_details: serializer.copilot_owner_details(payload[:owner]),
      seat: serializer.copilot_seat(payload[:seat]),
      other_cfb_organization_analytics_tracking_ids: other_cfb_organization_analytics_tracking_ids,
      actor: serializer.user(payload[:actor]),
      copilot_for_business_details: serializer.copilot_for_business_details(payload[:details]),
      event_type: payload[:event_type].to_s
    }

    publish(message, schema: "github.copilot.v2.CopilotForBusinessSeatCancelled")
    copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
    if FeatureFlag.vexi.enabled?(:copilot_instrument_copilot_license_or_billable_customer_change, copilot_user.user_object, default: false) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(Copilot::Public::User.new(copilot_user.user_object))
    end
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_CANCELLED_BY_STAFF) do |payload|
    copilot_user = Copilot::User.new(payload[:user])
    other_cfb_organization_analytics_tracking_ids = copilot_user.orgs_having_copilot_for_business.collect(&:analytics_tracking_id).to_s

    message = {
      user: serializer.user(payload[:user]),
      owner_details: serializer.copilot_owner_details(payload[:owner]),
      seat: serializer.copilot_seat(payload[:seat]),
      other_cfb_organization_analytics_tracking_ids: other_cfb_organization_analytics_tracking_ids,
      actor: serializer.user(payload[:actor]),
      event_type: payload[:event_type].to_s,
      copilot_for_business_details: serializer.copilot_for_business_details(payload[:details]),
    }

    publish(message, schema: "github.copilot.v2.CopilotForBusinessSeatCancelledByStaff")
    copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
    if FeatureFlag.vexi.enabled?(:copilot_instrument_copilot_license_or_billable_customer_change, copilot_user.user_object, default: false)
      Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(Copilot::Public::User.new(copilot_user.user_object))
    end
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_EMISSION) do |payload|
    seat_emission = payload[:seat_emission]

    message = {
      owner_details: serializer.copilot_owner_details(payload[:owner]),
      already_billed_user_ids_count: payload[:already_billed_user_ids_count],
      number_of_days_in_billing_cycle: payload[:number_of_days_in_billing_cycle],
      per_seat_rate: payload[:per_seat_rate],
      quantity: seat_emission.quantity.to_f,
      seat_count: payload[:seat_count],
      seat_emission: serializer.copilot_seat_emission(payload[:seat_emission]),
      source_uri: seat_emission.source_uri,
      usage_at: Google::Protobuf::Timestamp.new(seconds: seat_emission.usage_at.to_i, nanos: 0),
      usage_uuid: seat_emission.usage_uuid,
    }

    publish(message, schema: "github.copilot.v2.CopilotForBusinessSeatEmissionCreated")
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_EMISSION_SKIPPED) do |payload|
    message = {
      owner_details: serializer.copilot_owner_details(payload[:owner]),
      reason: payload[:reason],
    }

    publish(message, schema: "github.copilot.v2.CopilotForBusinessSeatEmissionSkipped")
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_MANAGEMENT_CHANGED) do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      copilot_for_business_details: serializer.copilot_for_business_details(payload[:details]),
      new_value: payload[:new_value],
      owner_details: serializer.copilot_owner_details(payload[:organization]),
      previous_value: payload[:old_value],
    }

    publish(message, schema: "github.copilot.v2.CopilotForBusinessOrganizationSeatManagementChanged")
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_UNCANCELLED_BY_STAFF) do |payload|
    seat = payload[:seat]
    next if seat.nil?

    user = seat.assigned_user
    staff_actor = payload[:staff_actor]

    copilot_user = Copilot::User.new(seat.assigned_user)
    other_cfb_organization_analytics_tracking_ids = copilot_user.orgs_having_copilot_for_business.collect(&:analytics_tracking_id).to_s

    message = {
      user: serializer.user(user),
      owner_details: serializer.copilot_owner_details(seat.seat_assignment&.owner),
      seat: serializer.copilot_seat(seat),
      other_cfb_organization_analytics_tracking_ids: other_cfb_organization_analytics_tracking_ids,
      staff_actor: serializer.user(staff_actor),
      copilot_for_business_details: serializer.copilot_for_business_details(payload[:details]),
    }

    publish(message, schema: "github.copilot.v2.CopilotForBusinessSeatUncancelledByStaff")

    Copilot::BatchUpdateUserSettingsJob.perform_later(payload[:organization]&.id)
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_TRIAL_CREATED) do |payload|
    message = {
      staff_actor: serializer.user(payload[:staff_actor]),
      organization: serializer.organization(payload[:organization]),
      business: serializer.business(payload[:business]),
      seat_count: payload[:seat_count],
      trial_duration_days: payload[:trial_duration_days],
      copilot_plan: serializer.copilot_plan(payload[:copilot_plan]),
    }

    publish(message, schema: "github.copilot.v2.CopilotForBusinessTrialCreated")

    Copilot::BatchUpdateUserSettingsJob.perform_later(payload[:organization]&.id)
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_TRIAL_ENDED) do |payload|
    message = {
      organization: serializer.organization(payload[:organization]),
      business: serializer.business(payload[:business]),
      seat_count: payload[:seat_count],
      trial_duration_days: payload[:trial_duration_days],
      trial_started_at: Google::Protobuf::Timestamp.new(seconds: payload[:trial_started_at].to_i, nanos: 0),
      trial_ended_at: Google::Protobuf::Timestamp.new(seconds: payload[:trial_ended_at].to_i, nanos: 0),
      copilot_plan: serializer.copilot_plan(payload[:copilot_plan]),
    }

    publish(message, schema: "github.copilot.v2.CopilotForBusinessTrialEnded")

    Copilot::BatchUpdateUserSettingsJob.perform_later(payload[:organization]&.id)
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_TRIAL_STARTED) do |payload|
    org_admin = payload[:org_admin]
    trial = payload[:trial]
    organization = trial.trialable
    business = organization.business

    message = {
      admin: serializer.user(org_admin),
      organization: serializer.organization(organization),
      business: serializer.business(business),
      seat_count: 0, # trial.seat_count field will be deprecated
      trial_duration_days: trial.trial_length,
      trial_started_at: Google::Protobuf::Timestamp.new(seconds: trial.started_at.to_i, nanos: 0),
      trial_ends_at: Google::Protobuf::Timestamp.new(seconds: trial.ends_at.to_i, nanos: 0),
      copilot_plan: serializer.copilot_plan(trial.copilot_plan),
    }

    publish(message, schema: "github.copilot.v2.CopilotForBusinessTrialStarted")

    Copilot::BatchUpdateUserSettingsJob.perform_later(payload[:organization]&.id)
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_TRIAL_UPGRADED) do |payload|
    staff_actor = payload[:staff_actor]
    trial = payload[:trial]
    organization = trial.trialable
    business = organization.business

    message = {
      staff_actor: serializer.user(staff_actor),
      organization: serializer.organization(organization),
      business: serializer.business(business),
      seat_count: 0, # trial.seat_count field will be deprecated
      trial_duration_days: trial.trial_length,
      trial_started_at: Google::Protobuf::Timestamp.new(seconds: trial.started_at.to_i, nanos: 0),
      trial_ended_at: Google::Protobuf::Timestamp.new(seconds: trial.ends_at.to_i, nanos: 0),
      copilot_plan: serializer.copilot_plan(trial.copilot_plan),
    }

    publish(message, schema: "github.copilot.v2.CopilotForBusinessTrialUpgraded")
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_TRIAL_EXTENDED) do |payload|
    staff_actor = payload[:staff_actor]
    trial = payload[:trial]
    organization = trial.trialable
    business = organization.business

    message = {
      staff_actor: serializer.user(staff_actor),
      organization: serializer.organization(organization),
      business: serializer.business(business),
      seat_count: payload[:seat_count],
      trial_duration_days: payload[:trial_duration_days],
      copilot_plan: serializer.copilot_plan(trial.copilot_plan),
    }

    publish(message, schema: "github.copilot.v2.CopilotForBusinessTrialExtended")
  end

  subscribe(::Copilot::Events::COPILOT_FOR_BUSINESS_TRIAL_CHANGED) do |payload|
    staff_actor = payload[:staff_actor]
    trial = payload[:trial]
    organization = trial.trialable
    business = organization.business

    message = {
      staff_actor: serializer.user(staff_actor),
      organization: serializer.organization(organization),
      business: serializer.business(business),
      previous_trial_ends_at: Google::Protobuf::Timestamp.new(seconds: payload[:previous_trial_ends_at].to_i, nanos: 0),
      updated_trial_ends_at: Google::Protobuf::Timestamp.new(seconds: trial.ends_at.to_i, nanos: 0),
      reason: payload[:reason],
      old_copilot_plan: serializer.copilot_plan(payload[:old_copilot_plan]),
      new_copilot_plan: serializer.copilot_plan(trial.copilot_plan),
    }

    publish(message, schema: "github.copilot.v2.CopilotForBusinessTrialChanged")
  end

  subscribe(::Copilot::Events::COPILOT_PLAN_CHANGED) do |payload|

    message = {
      actor: serializer.user(payload[:actor]),
      old_plan: serializer.copilot_plan(payload[:old_plan]),
    }

    owner = payload[:owner]
    if owner.is_a?(::Business)
      # This should not be happening anymore with mixed licenses
      copilot_business = Copilot::Business.new(owner)
      message[:business] = serializer.business(owner)
      message[:plan] = serializer.copilot_plan(copilot_business.copilot_plan)
    elsif owner.is_a?(::Organization)
      copilot_organization = Copilot::Organization.new(owner)
      message[:organization] = serializer.organization(owner)
      message[:plan] = serializer.copilot_plan(copilot_organization.copilot_plan)
      Copilot::BatchUpdateUserSettingsJob.perform_later(copilot_organization.id)
    end

    publish(message, schema: "github.copilot.v2.CopilotPlanChanged")
  end

  # this is when an org or business's copilot access is revoked
  subscribe(::Copilot::Events::COPILOT_ACCESS_REVOKED) do |payload|
    message = {
      owner_details: serializer.copilot_owner_details(payload[:owner]),
      copilot_plan: serializer.copilot_plan(payload[:plan]),
      reason: payload[:reason],
    }

    publish(message, schema: "github.copilot.v2.CopilotAccessRevoked")
  end

  # this is when a user's copilot access is revoked
  subscribe(::Copilot::Events::COPILOT_USER_ACCESS_REVOKED) do |payload|
    message = {
      seat_assignment: serializer.copilot_seat_assignment(payload[:assignment]),
      reason: payload[:reason],
      owner_details: serializer.copilot_owner_details(payload[:owner]),
      copilot_for_business_details: serializer.copilot_for_business_details(payload[:details]),
    }

    publish(message, schema: "github.copilot.v2.CopilotUserAccessRevoked")

    # regenerate the user settings cache if the assignable is a user who still exists and isn't suspended
    assignment = payload.dig(:assignment)
    if assignment&.assignable_type == "User"
      user = assignment.assignable
      if user.present? && !user.suspended?
        Copilot::User.new(user).create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
      end
    end
  end

  subscribe(::Copilot::Events::COPILOT_USER_ACCESS_REINSTATED) do |payload|
    message = {
      seat_assignment: serializer.copilot_seat_assignment(payload[:assignment]),
      reason: payload[:reason],
      owner_details: serializer.copilot_owner_details(payload[:owner]),
      copilot_for_business_details: serializer.copilot_for_business_details(payload[:details]),
    }

    publish(message, schema: "github.copilot.v2.CopilotUserAccessReinstated")
  end

  subscribe(::Copilot::Events::KNOWLEDGE_BASE_CREATED) do |payload|
    message = {
      user: serializer.user(payload[:actor]),
      organization: serializer.organization(payload[:organization]),
      organization_id: payload[:organization_id],
      knowledge_base_id: payload[:knowledge_base_id],
      knowledge_base_name: payload[:knowledge_base_name],
      knowledge_base_description: payload[:knowledge_base_description],
      number_of_repos: payload[:number_of_repos],
    }

    publish(message, schema: "github.copilot.v2.KnowledgeBaseCreated")
  end

  subscribe(::Copilot::Events::KNOWLEDGE_BASE_DELETED) do |payload|
    message = {
      user: serializer.user(payload[:actor]),
      organization: serializer.organization(payload[:organization]),
      organization_id: payload[:organization_id],
      knowledge_base_id: payload[:knowledge_base_id],
      knowledge_base_name: payload[:knowledge_base_name],
    }

    publish(message, schema: "github.copilot.v2.KnowledgeBaseDeleted")
  end

  subscribe(::Copilot::Events::KNOWLEDGE_BASE_UPDATED) do |payload|
    message = {
      user: serializer.user(payload[:actor]),
      organization: serializer.organization(payload[:organization]),
      organization_id: payload[:organization_id],
      knowledge_base_id: payload[:knowledge_base_id],
      knowledge_base_name: payload[:knowledge_base_name],
      knowledge_base_description: payload[:knowledge_base_description],
      number_of_repos: payload[:number_of_repos],
    }

    publish(message, schema: "github.copilot.v2.KnowledgeBaseUpdated")
  end

  subscribe(::Copilot::Events::COPILOT_CUSTOM_INSTRUCTIONS_CREATED) do |payload|
    next unless payload[:org].present?

    message = {
      user: serializer.user(payload[:actor]),
      organization: serializer.organization(payload[:org]),
      custom_instructions: payload[:custom_instructions],
      action: "created"
    }

    publish(message, schema: "github.copilot.v2.OrganizationCustomInstructionsChanged")
  end

  subscribe(::Copilot::Events::COPILOT_CUSTOM_INSTRUCTIONS_UPDATED) do |payload|
    next unless payload[:org].present?

    message = {
      user: serializer.user(payload[:actor]),
      organization: serializer.organization(payload[:org]),
      custom_instructions: payload[:custom_instructions],
      action: "updated"
    }

    publish(message, schema: "github.copilot.v2.OrganizationCustomInstructionsChanged")
  end
end
