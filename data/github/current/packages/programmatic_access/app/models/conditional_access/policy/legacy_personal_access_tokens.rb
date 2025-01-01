# typed: true
# frozen_string_literal: true

module ConditionalAccess
  module Policy
    module LegacyPersonalAccessTokens
      extend T::Helpers

      include ConditionalAccess::Helpers::OutsideCollaboratorChecks
      include ConditionalAccess::Helpers::TargetFilters

      requires_ancestor { Kernel }

      AppliedIn = T.type_alias do
        T.any(
          ConditionalAccess::Api::Internal::Enforcer,
          ConditionalAccess::Api::Public::Enforcer,
          ConditionalAccess::Api::Public::Filter,
          ConditionalAccess::GitAuth::Enforcer
        )
      end

      # Public: Has the target opted out of allowing a Legacy Personal Access
      # Token access to their resources?
      #
      # Returns :yes if the policy was applicable, otherwise :no.
      def legacy_personal_access_tokens_applicable(resource:, target_provider:)
        return :no unless request_via_legacy_pat?

        target = target_provider.target(resource)
        return :no unless target_applicable?(target)
        return :no unless target.legacy_personal_access_tokens_restricted?

        :yes
      end

      # Public: The policy is satisfied when the authenticating actor is not
      # using a Legacy Personal Access Token as the means of authentication.
      #
      # Returns :no if the actor is part of the organization or business
      #   otherwise :yes.
      def legacy_personal_access_tokens_satisfied(resource:, target_provider:)
        T.bind(self, AppliedIn)

        target = target_provider.target(resource)

        case target
        when Business
          return :no if actor.is_business_member?(target.id)
        when Organization
          # This mimics User#affiliated_with_organization? with a more
          # performant outside collaborator check.
          return :no if target.direct_or_team_member?(actor)
          return :no if target.billing_manager?(actor)
          return :no if actor_outside_collaborator_for_resource?(target, resource)
          return :no if actor_outside_collaborator_for_org?(target)
        end

        :yes
      end

      # Public: Computes the applicability of this policy for multiple
      # targets.
      #
      # targets - An Enumerable of targets for conditional access.
      # target_provider - An instance of ConditionalAccess::TargetProvider
      #
      # Returns an Array of targets where the policy was applicable.
      def multiple_legacy_personal_access_tokens_applicable(targets, target_provider)
        return [] unless request_via_legacy_pat?
        targets.filter { |target| target_applicable?(target) }
      end

      # Public: Computes the satisfiability of this policy for multiple targets.
      #
      # targets - An Enumerable of targets for conditional access.
      # target_provider - An instance of ConditionalAccess::TargetProvider
      #
      # Returns an Array of targets where the policy was satisfied.
      def multiple_legacy_personal_access_tokens_satisfied(targets, target_provider)
        result = Hash.new { |h, k| h[k] = {} }
        targets.each do |target|
          satisfied = true

          case target
          when Business
            @legacy_pat_restricted_business_ids ||= legacy_pat_restricted_business_ids
            satisfied = false if @legacy_pat_restricted_business_ids.include?(target.id)
          when Organization
            @legacy_pat_restricted_organization_ids ||= legacy_pat_restricted_organization_ids
            satisfied = false if @legacy_pat_restricted_organization_ids.include?(target.id)
          else
            raise ArgumentError.new("unsupported target for conditional access")
          end

          result[target] = {
            "private": satisfied ? :satisfied : :unsatisfied,
          }
        end
        result
      end

      # Internal: Find all of the actor's associated Businesses that are
      # restricting legacy personal access tokens.
      #
      # Returns an Array.
      def legacy_pat_restricted_business_ids
        T.bind(self, AppliedIn)

        business_ids = actor.business_ids
        business_ids_with_configuration_enabled(business_ids, Configurable::RestrictLegacyPersonalAccessTokens::KEY)
      end

      # Internal: Find all of the actors associated Organizations that are
      # restricting legacy personal access tokens.
      #
      # Returns an Array.
      def legacy_pat_restricted_organization_ids
        organization_ids_restricting_pat_access(configuration_key: Configurable::RestrictLegacyPersonalAccessTokens::KEY)
      end

      # Internal: Is the request actor and its means of authentication
      # applicable to the policy?
      #
      # Returns a Boolean.
      def request_via_legacy_pat?
        T.bind(self, AppliedIn)

        return false if anonymous?

        # Not applicable if the authenticating user isn't using a Legacy PAT.
        return false unless actor.instance_of?(User)

        actor.using_personal_access_token?
      end
    end
  end
end
