# typed: true
# frozen_string_literal: true

module ConditionalAccess
  module Policy
    module PersonalAccessTokens
      extend T::Helpers

      include ConditionalAccess::Helpers::OutsideCollaboratorChecks
      include ConditionalAccess::Helpers::TargetFilters

      requires_ancestor { Kernel }

      AppliedIn = T.type_alias do
        T.any(
          ConditionalAccess::Api::Internal::Enforcer,
          ConditionalAccess::Api::Public::Enforcer,
          ConditionalAccess::Api::Public::Filter,
          ConditionalAccess::CapGitAuth::Enforcer
        )
      end

      # Public: Has the target opted out of allowing a Personal Access Token
      # to access their resources?
      #
      # Returns :yes if the policy was applicable, otherwise :no.
      def personal_access_tokens_applicable(resource:, target_provider:)
        return :no unless request_via_user_programmatic_access?

        target = target_provider.target(resource)
        return :no unless target_applicable?(target)
        return :no unless target.personal_access_tokens_restricted?

        :yes
      end

      # Public: Computes the applicability of this policy for multiple
      # targets.
      #
      # targets - An Enumerable of targets for conditional access.
      # target_provider - An instance of ConditionalAccess::TargetProvider
      #
      # Returns an Array of targets where the policy was applicable.
      def multiple_personal_access_tokens_applicable(targets, target_provider)
        return [] unless request_via_user_programmatic_access?
        targets.filter { |target| target_applicable?(target) }
      end

      # Public: The policy is satisfied when the authenticating actor is not
      # using a Personal Access Token as the means of authentication.
      #
      # Returns :no if the actor is part of the organization or business
      #   otherwise :yes.
      def personal_access_tokens_satisfied(resource:, target_provider:)
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

      # Public: Computes the satisfiability of this policy for multiple targets.
      #
      # targets - An Enumerable of targets for conditional access.
      # target_provider - An instance of ConditionalAccess::TargetProvider
      #
      # Returns an Array of targets where the policy was satisfied.
      def multiple_personal_access_tokens_satisfied(targets, target_provider)
        result = Hash.new { |h, k| h[k] = {} }
        targets.each do |target|
          satisfied = true

          case target
          when Business
            @pat_restricted_business_ids ||= pat_restricted_business_ids
            satisfied = false if @pat_restricted_business_ids.include?(target.id)
          when Organization
            satisfied = false if pat_restricted_organizations_experiment(target.id, targets)
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
      # restricting personal access tokens.
      #
      # Returns an Array.
      def pat_restricted_business_ids
        T.bind(self, AppliedIn)

        business_ids = actor.business_ids
        business_ids_with_configuration_enabled(business_ids, Configurable::RestrictPersonalAccessTokens::KEY)
      end

      def pat_restricted_organizations_experiment(org_id, targets)
        pat_restricted_organization_ids_candidate(targets).include?(org_id)
      end

      # Internal: Find all of the actors associated Organizations that are
      # restricting personal access tokens.
      #
      # Returns an Array.
      def pat_restricted_organization_ids
        return @pat_restricted_organization_ids if defined?(@pat_restricted_organization_ids)

        @pat_restricted_organization_ids = organization_ids_restricting_pat_access(configuration_key: Configurable::RestrictPersonalAccessTokens::KEY)
      end

      def pat_restricted_organization_ids_candidate(targets)
        return @pat_restricted_organization_ids_candidate if defined?(@pat_restricted_organization_ids_candidate)

        @pat_restricted_organization_ids_candidate = organization_ids_restricting_pat_access_candidate(configuration_key: Configurable::RestrictPersonalAccessTokens::KEY, targets: targets)
      end

      # Internal: Is the request actor and its means of authentication
      # applicable to the policy?
      #
      # Returns a Boolean.
      def request_via_user_programmatic_access?
        T.bind(self, AppliedIn)

        return false if anonymous?
        # Not applicable if the authenticating user isn't using a PAT.
        return false unless actor.instance_of?(User)

        actor.using_auth_via_user_programmatic_access?
      end
    end
  end
end
