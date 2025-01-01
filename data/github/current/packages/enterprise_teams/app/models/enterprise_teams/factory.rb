# typed: strict
# frozen_string_literal: true

module EnterpriseTeams
  class Factory
    class BusinessTeamValidationError < StandardError; end

    sig do
      params(
        enterprise: T.untyped,
        team_name: String,
        sync_to_organizations: T.untyped,
        idp_group_id: T.untyped,
        is_security_manager: T::Boolean
      ).returns(EnterpriseTeam)
    end
    def self.create_enterprise_team(enterprise:, team_name:, sync_to_organizations:, idp_group_id:, is_security_manager:)
      # Create the enterprise team and group mapping (if applicable
      enterprise_team = EnterpriseTeam.new
      enterprise_team_group_mapping = T.let(nil, T.nilable(EnterpriseTeamGroupMapping))

      EnterpriseTeam.transaction do
        enterprise_team.business_id = enterprise.id
        enterprise_team.name = team_name
        if EnterpriseTeam.enabled_for_organizations?(business: enterprise)
          enterprise_team.sync_to_organizations = sync_to_organizations.to_s
        end
        enterprise_team.save!

        # Configure OSM sync if applicable
        EnterpriseTeams::Helper.configure_security_manager_sync(enterprise: enterprise, enterprise_team: enterprise_team, set_security_manager: is_security_manager)

        if idp_group_id.present?
          EnterpriseTeams::Helper.validate_idp_group_enterprise(enterprise, idp_group_id)
          enterprise_team_group_mapping = EnterpriseTeamGroupMapping.new
          enterprise_team_group_mapping.enterprise_team_id = enterprise_team.id
          enterprise_team_group_mapping.external_group_id = idp_group_id
          enterprise_team_group_mapping.save!
        end
      end

      # In the case sync_to_organizations is enabled, we need to generate the mappings + OTs
      EnterpriseTeamOrganizationMappingJob.perform_later(enterprise_team.id) if enterprise_team.sync_to_organizations? && EnterpriseTeam.enabled_for_organizations?(business: enterprise)
      enterprise_team
    end

    sig { params(enterprise: Business, team_name: String, description: String, organization_selection_type: Symbol, external_group_id: T.nilable(T.any(Integer, String))).returns(BusinessTeam) }
    def self.create_business_team(enterprise:, team_name:, description:, organization_selection_type: :disabled, external_group_id: nil)
      business_team = BusinessTeam.new
      business_team.business_id = enterprise.id

      validate_organization_selection_type(enterprise: enterprise, business_team: business_team, organization_selection_type: organization_selection_type)

      result = BusinessTeam.transaction do
        saved_team = save_business_team(business_team, team_name: team_name, description: description, organization_selection_type: organization_selection_type)

        if external_group_id.present?
          external_group = find_external_group(enterprise: enterprise, external_group_id: external_group_id)

          if external_group
            validate_external_group_link_membership_limits(enterprise: enterprise, external_group: external_group)

            external_group_team = ExternalGroupTeam.create!(
              team_id: saved_team.id,
              external_group_id: external_group.id
            )
          end
        end

        saved_team
      end

      if organization_selection_type == :all
        BusinessTeamOrgAssignmentsInstrumentationJob.perform_later(business_team, :all, [])
      end

      result
    end

    # Updates a business team
    # @param enterprise [Business] The enterprise the team belongs to
    # @param team_slug [String] The slug of the team to update
    # @param team_name [String] The new name for the team
    # @param description [String] The new description for the team
    # @param organization_selection_type [Symbol] The organization selection type (:all, :selected, or :disabled)
    # @param external_group_id [Integer, nil] The external group ID to associate, or nil to remove association
    # @return [Hash] Hash containing the updated business team and conversion flags
    sig { params(enterprise: Business, team_slug: String, team_name: String, description: String, organization_selection_type: Symbol, external_group_id: T.nilable(T.any(Integer, String))).returns(T::Hash[Symbol, T.untyped]) }
    def self.update_business_team(enterprise:, team_slug:, team_name:, description:, organization_selection_type: :disabled, external_group_id: nil)
      business_team = BusinessTeam.find_by!(business: enterprise, slug: BusinessTeam.to_model_slug(team_slug))
      validate_organization_selection_type(enterprise: enterprise, business_team: business_team, organization_selection_type: organization_selection_type)
      previous_org_ids = business_team.organization_ids
      result = BusinessTeam.transaction do
        if organization_selection_type == :selected && business_team.organization_selection_type.to_sym == :all
          # When switching from all to selected, we leave organization_selection_type as :all until CreateBusinessTeamOrgAssignmentJob finishes running (enqueued later in this method)
          # Otherwise, users will briefly lose org memberships while org assignments are still being created
          save_business_team(business_team, team_name: team_name, description: description, organization_selection_type: :all)
        else
          if organization_selection_type == :all || organization_selection_type == :disabled
            business_team.business_team_org_assignments.destroy_all
          end
          save_business_team(business_team, team_name: team_name, description: description, organization_selection_type: organization_selection_type)
        end

        conversion_result = update_team_external_group(enterprise, business_team, external_group_id)

        business_team.reload unless enterprise.feature_flag_enabled?(:enterprise_teams_audit_logs, default: false)

        {
          team: business_team,
          converted_to_external_group: conversion_result[:converted_to_external_group],
          converted_to_manual: conversion_result[:converted_to_manual],
          external_group_switched: conversion_result[:external_group_switched]
        }
      end

      if organization_selection_type == :all || organization_selection_type == :disabled
        BusinessTeamOrgAssignmentsInstrumentationJob.perform_later(
          business_team,
          organization_selection_type,
          previous_org_ids
        )
      end

      had_any_orgs = previous_org_ids.any?
      has_any_orgs = business_team.has_any_orgs?
      business_team.update_buas if had_any_orgs != has_any_orgs

      if had_any_orgs && !has_any_orgs
        ClearBusinessTeamIndirectOrgAccessJob.enqueue(
          business_id: enterprise.id,
          team_id: business_team.id,
          clear_team_roles: true,
          organization_ids: previous_org_ids,
        )
      end

      if organization_selection_type == :selected && business_team.organization_selection_type.to_sym == :all
        CreateBusinessTeamOrgAssignmentsJob.enqueue(result[:team])
      end

      result
    end

    sig { params(business_team: BusinessTeam, team_name: String, description: String, organization_selection_type: Symbol).returns(BusinessTeam) }
    private_class_method def self.save_business_team(business_team, team_name:, description:, organization_selection_type:)
      business_team.name = team_name
      business_team.description = description
      business_team.organization_selection_type = organization_selection_type

      begin
        business_team.save!
        business_team
      rescue ActiveRecord::StatementInvalid => ex
        # Prioritize our own unicode3 validation instead of the generic collation error.
        if business_team.errors.any?
          raise ActiveRecord::RecordInvalid, business_team
        end
        raise ex
      end
    end

    # Handle external group association for a business team
    # @param enterprise [Enterprise] The enterprise the team belongs to
    # @param business_team [BusinessTeam] The business team to update
    # @param external_group_id [Integer, nil] The external group ID to associate, or nil to remove association
    # @return [Hash] Hash containing conversion and external group switch flags
    sig { params(enterprise: Business, business_team: BusinessTeam, external_group_id: T.nilable(T.any(Integer, String))).returns(T::Hash[Symbol, T::Boolean]) }
    private_class_method def self.update_team_external_group(enterprise, business_team, external_group_id)
      conversion_occurred = false
      reverse_conversion_occurred = false
      external_group_switched = false

      if external_group_id.present?
        external_group = find_external_group(enterprise: enterprise, external_group_id: external_group_id)

        if external_group
          # Check if there's already an external group team association
          existing_group_team = business_team.external_group_team
          current_group_id = existing_group_team&.external_group_id

          # Only update if the external group has changed
          if current_group_id != external_group.id
            validate_external_group_link_membership_limits(enterprise: enterprise, external_group: external_group)

            # Check if this is a conversion from manual to IDP group management
            conversion_occurred = existing_group_team.nil?

            # Check if this is switching between different IdP groups
            external_group_switched = existing_group_team.present? && !conversion_occurred

            if existing_group_team
              # Update the existing association instead of destroying and recreating it
              existing_group_team.update!(external_group_id: external_group.id)
            else
              # Create a new association if none exists
              external_group_team = ExternalGroupTeam.create!(
                team_id: business_team.id,
                external_group_id: external_group.id
              )
              business_team.external_group_team = external_group_team if enterprise.feature_flag_enabled?(:enterprise_teams_audit_logs, default: false)
            end

            if conversion_occurred
              GitHub.logger.info(
                "code.namespace" => self.name,
                "code.function" =>  __method__,
                "info.message" => "Team converted from manual to IDP group management",
                "gh.business_team.id" => business_team.id,
                "gh.external_group.id" => external_group.id
              )
            elsif external_group_switched
              GitHub.logger.info(
                "code.namespace" => self.name,
                "code.function" =>  __method__,
                "info.message" => "Team switched between IdP groups",
                "gh.business_team.id" => business_team.id,
                "gh.previous_external_group.id" => current_group_id,
                "gh.new_external_group.id" => external_group.id
              )
            end
          else
            # Skip destroy/create if the group ID is the same
            # This avoids unnecessary unlinking and relinking when the team is updated
            # but the external group association hasn't changed
            GitHub.logger.info(
              "code.namespace" => self.name,
              "code.function" =>  __method__,
              "info.message" => "Skipping external group team association update - same group ID",
              "gh.business_team.id" => business_team.id,
              "gh.external_group.id" => external_group.id
            )
          end
        end
      else
        # If external_group_id is nil but there was an existing association
        ext_group_team = business_team.external_group_team

        if ext_group_team.present?
          # This is a reverse conversion (IDP group management to manual)
          reverse_conversion_occurred = true

          GitHub.logger.info(
            "code.namespace" => self.name,
            "code.function" =>  __method__,
            "info.message" => "Team converted from IDP group management to manual",
            "gh.business_team.id" => business_team.id,
            "gh.external_group.id" => ext_group_team.external_group_id
          )

          # Destroy the association - this will trigger the before_action hook that handles unlinking
          ext_group_team.destroy
          business_team.external_group_team = nil if enterprise.feature_flag_enabled?(:enterprise_teams_audit_logs, default: false)
        end
      end

      {
        converted_to_external_group: conversion_occurred,
        converted_to_manual: reverse_conversion_occurred,
        external_group_switched: external_group_switched
      }
    end

    sig { params(enterprise: Business, external_group_id: T.any(Integer, String)).returns(T.nilable(ExternalGroup)) }
    private_class_method def self.find_external_group(enterprise:, external_group_id:)
      scope = enterprise.external_provider&.external_groups&.not_deleted
      return unless scope
      scope.find_by(id: external_group_id) || scope.find_by(guid: external_group_id)
    end

    # Validates that the external group member count does not exceed business team member limit
    # @param enterprise [Business] The enterprise to check the limit for
    # @param external_group [ExternalGroup] The external group to validate
    # @raise [BusinessTeamValidationError] If the external group member count exceeds the limit
    sig { params(enterprise: Business, external_group: ExternalGroup).void }
    private_class_method def self.validate_external_group_link_membership_limits(enterprise:, external_group:)
      external_group_member_count = external_group.active_members_count

      if external_group_member_count > enterprise.business_team_member_limit
        raise BusinessTeamValidationError.new "The #{external_group.display_name} group has #{external_group_member_count} members, exceeding the #{enterprise.business_team_member_limit}-member team limit."
      end
    end

    sig { params(enterprise: Business, business_team: BusinessTeam, organization_selection_type: Symbol).void }
    private_class_method def self.validate_organization_selection_type(enterprise:, business_team:, organization_selection_type: :disabled)
      unless BusinessTeam.organization_selection_types.include?(organization_selection_type.to_sym)
        raise BusinessTeamValidationError.new "Invalid organization selection type: #{organization_selection_type}. Valid options are: #{BusinessTeam.organization_selection_types.keys.join(', ')}."
      end

      if organization_selection_type == :all
        if enterprise.organizations.count > enterprise.business_team_organization_assignment_limit
          raise BusinessTeamValidationError.new "Cannot create a team with organization selection type 'all' because the enterprise has more organizations than the limit. Please use 'selected' or 'disabled'."
        end
        status = business_team.bulk_validate_add_member_seats(business_team.member_ids, is_add_org_check: true)
        raise BusinessTeamValidationError.new status.message if status.is_a?(Team::AddOrganizationStatus) && status.error?
      end

      # If a team is assigned the Enterprise Security Manager (ESM) role, its organization selection type must remain :all.
      # If the org assignment limit is exceeded, the selection type is allowed to be :selected
      if business_team.assigned_enterprise_security_manager?
        exceeds_org_limit = enterprise.organizations.count > enterprise.business_team_organization_assignment_limit
        unless organization_selection_type == :all || (organization_selection_type == :selected && exceeds_org_limit)
          raise BusinessTeamValidationError.new(
            "Cannot change organization selection type to \"#{organization_selection_type}\" because the team is assigned the Enterprise Security Manager role. Please remove the Enterprise Security Manager role before changing the organization selection type."
          )
        end
      end
    end
  end
end
