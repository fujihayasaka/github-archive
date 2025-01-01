# typed: strict
# frozen_string_literal: true

module SecurityProduct
  class EnterpriseSecurityManagerRole
    private_class_method :new

    class << self
      # Public: Does the team have the enterprise security manager role granted directly to it?
      #
      # Returns a Boolean
      sig { params(team: EnterpriseTeam).returns(T::Boolean) }
      def granted?(team)
        UserRole.where(
          actor: team,
          role: Role.enterprise_security_manager_role,
          target_id: T.must(team.business).id,
          target_type: "Business"
        ).exists?
      end

      # Public: Adds the provided team to the enterprise's security managers.
      # If the provided team was already a security manager for the enterprise, this method does nothing.
      sig { params(team: EnterpriseTeam).void }
      def grant!(team)
        unless granted?(team)
          role_granter(team).grant!
          instrument_event("business.add_security_manager", team: team)
        end
      end

      # Public: Removes the provided team from the enterprise's security managers.
      # If the provided team isn't a security manager, this method does nothing.
      #
      # Raises GrantFailure if revoking was not successful.
      sig { params(team: EnterpriseTeam, caller: Symbol).void }
      def revoke!(team, caller: :user)
        if granted?(team)
          role_granter(team).revoke_if_exists!
          instrument_event("business.remove_security_manager", team: team)
        end
      end

      private

      sig { params(team: EnterpriseTeam).returns(::Permissions::Granters::RoleGranter) }
      def role_granter(team)
        ::Permissions::Granters::RoleGranter.new(
          actor: team,
          target: team.business,
          role: Role.enterprise_security_manager_role
        )
      end

      sig { params(event: String, team: EnterpriseTeam).void }
      def instrument_event(event, team:)
        business = T.must(team.business)
        payload = {
          business:,
          business_id: business.id,
          enterprise_team: team.slug,
          enterprise_team_id: team.id,
        }

        GitHub.instrument(event, payload)
      end
    end
  end
end
