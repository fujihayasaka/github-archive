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

      validate_organization_selection_type(enterprise: enterprise, organization_selection_type: organization_selection_type)

      BusinessTeam.transaction do
        saved_team = save_business_team(business_team, team_name: team_name, description: description, organization_selection_type: organization_selection_type)

        if external_group_id.present?
          external_group = find_external_group(enterprise: enterprise, external_group_id: external_group_id)

          if external_group
            validate_external_group_link_membershipship_limits(enterprise: enterprise, external_group: external_group)

            external_group_team = ExternalGroupTeam.create!(
              team_id: saved_team.id,
              external_group_id: external_group.id
            )
          end
        end

        saved_team
      end
    end

    # Updates a business team
    # @param enterprise [Business] The enterprise the team belongs to
    # @param team_slug [String] The slug of the team to update
    # @param team_name [String] The new name for the team
    # @param description [String] The new description for the team
    # @param organization_selection_type [Symbol] The organization selection type (:all, :selected, or :disabled)
    # @param external_group_id [Integer, nil] The external group ID to associate, or nil to remove association
    # @return [BusinessTeam] The updated business team
    sig { params(enterprise: Business, team_slug: String, team_name: String, description: String, organization_selection_type: Symbol, external_group_id: T.nilable(T.any(Integer, String))).returns(BusinessTeam) }
    def self.update_business_team(enterprise:, team_slug:, team_name:, description:, organization_selection_type: :disabled, external_group_id: nil)
      business_team = BusinessTeam.find_by!(business: enterprise, slug: BusinessTeam.to_model_slug(team_slug))
      validate_organization_selection_type(enterprise: enterprise, organization_selection_type: organization_selection_type)
      saved_team = BusinessTeam.transaction do
        if organization_selection_type == :selected && business_team.organization_selection_type.to_sym == :all
          # When switching from all to selected, we leave organization_selection_type as :all until CreateBusinessTeamOrgAssignmentJob finishes running (enqueued later in this method)
          # Otherwise, users will briefly lose org memberships while org assignments are still being created
          save_business_team(business_team, team_name:, description:, organization_selection_type: :all)
        else
          if organization_selection_type == :all || organization_selection_type == :disabled
            business_team.business_team_org_assignments.destroy_all
          end
          save_business_team(business_team, team_name:, description:, organization_selection_type:)
        end

        update_team_external_group(enterprise, business_team, external_group_id)

        business_team.reload
      end

      if organization_selection_type == :selected && business_team.organization_selection_type.to_sym == :all
        CreateBusinessTeamOrgAssignmentsJob.enqueue(saved_team)
      end

      saved_team
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
    sig { params(enterprise: Business, business_team: BusinessTeam, external_group_id: T.nilable(T.any(Integer, String))).void }
    private_class_method def self.update_team_external_group(enterprise, business_team, external_group_id)
      if external_group_id.present?
        external_group = find_external_group(enterprise: enterprise, external_group_id: external_group_id)

        if external_group
          # Check if there's already an external group team association
          existing_group_team = business_team.external_group_team
          current_group_id = existing_group_team&.external_group_id

          # Only destroy and recreate if the external group has changed
          if current_group_id != external_group.id
            validate_external_group_link_membershipship_limits(enterprise: enterprise, external_group: external_group)

            # Remove existing association if present and different from the new one
            existing_group_team&.destroy

            # Create the new association
            ExternalGroupTeam.create!(
              team_id: business_team.id,
              external_group_id: external_group.id
            )
          else
            # Skip destroy/create if the group ID is the same
            # This avoids unnecessary unlinking and relinking when the team is updated
            # but the external group association hasn't changed
            GitHub.logger.info(
              "code.namespace" => "EnterpriseTeams::Factory",
              "code.function" => "update_team_external_group",
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
          # Destroy the association - this will trigger the before_action hook that handles unlinking
          ext_group_team.destroy
        end
      end
    end

    sig { params(enterprise: Business, external_group_id: T.any(Integer, String)).returns(T.nilable(ExternalGroup)) }
    private_class_method def self.find_external_group(enterprise:, external_group_id:)
      scope = enterprise.external_provider&.external_groups&.not_deleted
      return unless scope
      scope.find_by(id: external_group_id) || scope.find_by(guid: external_group_id)
    end

    sig { params(enterprise: Business, external_group: ExternalGroup).void }
    private_class_method def self.validate_external_group_link_membershipship_limits(enterprise:, external_group:)
      external_group_member_count = external_group.active_members_count

      if external_group_member_count > enterprise.business_team_member_limit
        raise BusinessTeamValidationError.new "IdP group member count exceeds enterprise team product limits"
      end
    end

    sig { params(enterprise: Business, organization_selection_type: Symbol).void }
    private_class_method def self.validate_organization_selection_type(enterprise:, organization_selection_type: :disabled)
      unless BusinessTeam.organization_selection_types.include?(organization_selection_type.to_sym)
        raise BusinessTeamValidationError.new "Invalid organization selection type: #{organization_selection_type}. Valid options are: #{BusinessTeam.organization_selection_types.keys.join(', ')}."
      end

      if organization_selection_type == :all && enterprise.organizations.count > enterprise.business_team_organization_assignment_limit
        raise BusinessTeamValidationError.new "Cannot create a team with organization selection type 'all' because the enterprise has more organizations than the limit. Please use 'selected' or 'disabled'."
      end
    end
  end
end
