# typed: true
# frozen_string_literal: true

module Org
  class BulkMembersExport

    attr_reader :organization, :current_user, :for_site_admin

    FILTER_CSV_OPERATORS_REGEX = /\A[\s\=\-\+\@\;]/

    def initialize(format: "json", organization:, current_user:, for_site_admin: false)
      @format = format
      @organization = organization
      @current_user = current_user
      @for_site_admin = for_site_admin
    end

    def run
      members = GitHub.dogstats.time("members.export", tags: %W(action:fetch exporter:#{@backend})) do
        get_org_members
      end
      data = members.map do |member|
        row = {
          login: member.login,
          name: member.profile_name&.match(FILTER_CSV_OPERATORS_REGEX) ? "" : member.profile_name, # example: https://rubular.com/r/vGRX5h9XKbY3Sj
          tfa_enabled: member.two_factor_authentication_enabled?,
          is_public: @organization.public_member?(member),
          role: Organization::Role.name_for_type(@organization.role_of(member).type),
          saml_name_id: get_saml_name_id(member)
        }

        # This field is completely useless to org admins as it includes _all_ of a user's activity on GitHub, and even then it has major holes.
        # See https://github.com/github/licensing/issues/2219#issuecomment-3134543734
        unless @organization.feature_flag_enabled?(:hide_org_broken_last_active, default: false)
          row[:last_active] = member.last_active
        end

        if @organization.feature_flag_enabled?(:org_members_2fa_level, default: false)
          row[:tfa_level] = tfa_level(member)
        end
        if !member.two_factor_authentication_enabled? && member.has_forthcoming_account_two_factor_requirement?
          row[:tfa_required_by] = member&.two_factor_requirement_metadata&.required_by
        end

        if should_display_guest_collaborator?
          row[:is_guest_collaborator] = member.guest_collaborator?
        end

        if should_display_org_roles_count?
          row[:organization_roles_count] = get_organization_roles_count(member)
        end

        row
      end

      format_data(data)
    end

    def get_org_members
      return org_members_for_site_admin if for_site_admin

      people_query = Organization::People::Query.new(
        query: nil,
        organization: organization,
        current_user: current_user,
        role: nil
      )
      users = Organization::People::Filter.new(query: people_query).call
      Organization::People::Search.new(query: people_query, users: users).call
    end

    def org_members_for_site_admin
      organization.members.includes(:profile)
    end

    def get_saml_name_id(user)
      return nil if @organization.saml_provider.nil? && @organization.business&.saml_provider.nil?
      user.external_identities.find do |external_identity|
        if external_identity.provider.is_a?(Business::SamlProvider)
          external_identity.provider.business == @organization.business
        elsif external_identity.provider.is_a?(Organization::SamlProvider)
          external_identity.provider.organization == @organization if external_identity.provider.is_a?(Organization::SamlProvider)
        end
      end&.name_id
    end

    def format_in_csv(rows, fields, include_header: true)
      CSV.generate do |csv|
        csv << fields if include_header
        rows.each do |row|
          csv << fields.collect do |field|
            matches = field.match(/\Adata\.(?<field>[A-Za-z_]+)\z/)
            row[field]
          end
        end
      end
    end

    def format_data(data)
      case @format
      when "json"
        GitHub::JSON.encode(data)
      when "csv"
        if should_display_guest_collaborator?
          if should_display_org_roles_count?
            format_in_csv(data, csv_fields + [:is_guest_collaborator, :organization_roles_count])
          else
            format_in_csv(data, csv_fields + [:is_guest_collaborator])
          end
        elsif should_display_org_roles_count? # separate ff
          format_in_csv(data, csv_fields + [:organization_roles_count])
        else
          format_in_csv(data, csv_fields)
        end
      else
        raise ArgumentError, "invalid format '#{@format}' expected: json, csv"
      end
    end

    def csv_fields
      fields = %w[
        login
        name
        tfa_enabled
        tfa_required_by
        is_public
        role
        last_active
        saml_name_id
      ].map(&:to_sym)
      if @organization.feature_flag_enabled?(:hide_org_broken_last_active, default: false)
        fields.delete(:last_active)
      end
      if @organization.feature_flag_enabled?(:org_members_2fa_level, default: false)
        fields.insert(3, :tfa_level)
      end
      fields
    end

    def get_organization_roles_count(member)
      team_ids = organization.teams_for(member, viewer: current_user, with_business_teams: organization.business&.enterprise_teams_org_roles_supported?).pluck(:id)
      user_roles = UserRole.includes(:role).where(
        target_type: "Organization", target_id: organization.id,
        actor_type: "User", actor_id: member.id,
        role: OrganizationRole.custom_roles_for_org(organization)
      ).count

      if organization.business&.enterprise_teams_org_roles_supported?
        team_roles = UserRole.includes(:role).where(
          target_type: "Organization", target_id: organization.id,
          actor_type: %w[Team BusinessTeam], actor_id: team_ids,
          role: OrganizationRole.custom_roles_for_org(organization)
        ).count
      else
        team_roles = UserRole.includes(:role).where(
          target_type: "Organization", target_id: organization.id,
          actor_type: "Team", actor_id: team_ids,
          role: OrganizationRole.custom_roles_for_org(organization)
        ).count
      end

      user_roles + team_roles
    end

    def should_display_org_roles_count?
      organization.adminable_by?(@current_user)
    end

    def should_display_guest_collaborator?
      organization.enterprise_managed_user_enabled?
    end

    private def tfa_level(user)
      if user.has_any_given_2fa_methods_configured?([:insecure])
        "insecure"
      elsif user.two_factor_authentication_enabled?
        "secure"
      else
        "disabled"
      end
    end
  end
end
