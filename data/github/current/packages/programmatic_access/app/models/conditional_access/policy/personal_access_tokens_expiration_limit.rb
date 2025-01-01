# typed: true
# frozen_string_literal: true

module ConditionalAccess
  module Policy
    module PersonalAccessTokensExpirationLimit
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

      # Public: Has the target set an expiration limit for Personal Access Tokens?
      #
      # Returns :yes if the policy was applicable, otherwise :no.
      def personal_access_tokens_expiration_limit_applicable(resource:, target_provider:)
        return :no unless request_via_personal_access_token?

        target = target_provider.target(resource)

        return :no unless target_applicable_for_lifetime_policy?(target)
        return :no if ProgrammaticAccessTokenLifetimeConfiguration.expiration_limit_for(target, expirable_access.pat_type).blank?
        return :no if actor_exempted?(target)

        :yes
      end

      # Public: Computes the applicability of this policy for multiple
      # targets.
      #
      # targets - An Enumerable of targets for conditional access.
      # target_provider - An instance of ConditionalAccess::TargetProvider
      #
      # Returns an Array of targets where the policy was applicable.
      def multiple_personal_access_tokens_expiration_limit_applicable(targets, target_provider)
        GitHub.tracer.in_span("cap.personal_access_tokens_expiration_limit.applicable.filtering", kind: :internal) do |span|
          span.add_attributes({ "gh.targets_size" => targets.size })
          return [] unless request_via_personal_access_token?
          targets.filter do |target|
            span.add_attributes({ "gh.target.id" => target.respond_to?(:id) ? target.id : nil, "gh.target.type" => target.class.name })
            target_applicable_for_lifetime_policy?(target)
          end
        end
      end

      # Public: The policy is satisfied when the authenticating actor's PAT does
      # not exceed the expiration limit set by the target.
      #
      # Returns :yes if the actor's PAT adheres to the expiration limit set by the target,
      # otherwise :no.
      def personal_access_tokens_expiration_limit_satisfied(resource:, target_provider:)
        target = target_provider.target(resource)

        case target
        when Business
          # If the actor isn't affiliated with the business, then the policy doesn't apply.
          return :yes unless T.cast(self, AppliedIn).actor.is_business_member?(target.id)
        when Organization
          return :yes unless actor_affiliated_with_org?(T.cast(self, AppliedIn).actor, target, resource)
        end

        return :no unless expirable_access.pat_adheres_by_targets_expiration_limit?(target)

        :yes
      end

      # Public: Computes the satisfiability of this policy for multiple targets.
      #
      # targets - An Enumerable of targets for conditional access.
      # target_provider - An instance of ConditionalAccess::TargetProvider
      #
      # Returns an Array of targets where the policy was satisfied.
      def multiple_personal_access_tokens_expiration_limit_satisfied(targets, target_provider)
        GitHub.tracer.in_span("cap.personal_access_tokens_expiration_limit.satisfied.filtering", kind: :internal) do |span|
          span.add_attributes({ "gh.targets_size" => targets.size })
          result = Hash.new { |h, k| h[k] = {} }
          targets.each do |target|
            satisfied = true

            span.add_attributes({ "gh.target.id" => target.respond_to?(:id) ? target.id : nil, "gh.target.type" => target.class.name })

            case target
            when Business
              satisfied = false if pat_expiration_limit_unsatisfied_business_ids.include?(target.id)
            when Organization
              satisfied = false if org_expiration_science_experiment(target.id, targets)
            when User
              satisfied = true

              if target.user? && (target.is_enterprise_managed? || GitHub.enterprise?)
                business = GitHub.enterprise? ? GitHub.global_business : target.enterprise_managed_business
                satisfied = !pat_expiration_limit_unsatisfied_business_ids.include?(business.id)
              end
            else
              raise ArgumentError.new("unsupported target for conditional access")
            end

            result[target] = {
              "private": satisfied ? :satisfied : :unsatisfied,
            }
          end
          result
        end
      end

      # Internal: Is the request actor and its means of authentication
      # applicable to the policy?
      #
      # Returns a Boolean.
      def request_via_personal_access_token?
        T.bind(self, AppliedIn)

        return false if anonymous?

        # Not applicable if the authenticating user isn't using a PAT.
        return false unless actor.instance_of?(User)

        # Applicable if the authenticating user is using a PATv1 or PATv2
        actor.using_auth_via_user_programmatic_access? || actor.using_personal_access_token?
      end

      # Internal: Find all of the actor's associated Businesses that enforce
      # an expiration policy the PAT doesn't adhere to.
      #
      # Returns an Array.
      def pat_expiration_limit_unsatisfied_business_ids
        return @pat_expiration_limit_unsatisfied_business_ids if defined?(@pat_expiration_limit_unsatisfied_business_ids)

        @pat_expiration_limit_unsatisfied_business_ids = business_ids_restricting_pat_lifetime(expirable_access.pat_lifetime_in_days, expirable_access.pat_type)
      end

      def org_expiration_science_experiment(org_id, targets)
        pat_expiration_limit_unsatisfied_org_ids_candidate(targets).include?(org_id)
      end

      # Internal: Find all of the actor's associated Orgs that enforce
      # an expiration policy the PAT doesn't adhere to.
      #
      # Returns an Array.
      def pat_expiration_limit_unsatisfied_org_ids
        return @pat_expiration_limit_unsatisfied_org_ids if defined?(@pat_expiration_limit_unsatisfied_org_ids)

        @pat_expiration_limit_unsatisfied_org_ids = organization_ids_restricting_pat_lifetime(expirable_access.pat_lifetime_in_days, expirable_access.pat_type)
      end

      def pat_expiration_limit_unsatisfied_org_ids_candidate(targets)
        return @pat_expiration_limit_unsatisfied_org_ids_candidate if defined?(@pat_expiration_limit_unsatisfied_org_ids_candidate)

        @pat_expiration_limit_unsatisfied_org_ids_candidate = organization_ids_restricting_pat_lifetime_candidate(
          expirable_access.pat_lifetime_in_days,
          expirable_access.pat_type,
          targets: targets
        )
      end

      # TODO move to module
      def actor_affiliated_with_org?(actor, org, resource)
        return @actor_affiliated_with_org if defined?(@actor_affiliated_with_org)

        # This mimics User#affiliated_with_organization? with a more
        # performant outside collaborator check.
        @actor_affiliated_with_org = org.direct_or_team_member?(actor) || org.billing_manager?(actor) || actor_outside_collaborator_for_resource?(org, resource) || actor_outside_collaborator_for_org?(org)
      end

      # Internal: The actor's programmatic access.
      #
      # Returns an instance of UserProgrammaticAccess or OAuthAccess.
      def expirable_access
        T.bind(self, AppliedIn)

        actor.programmatic_access || actor.oauth_access
      end

      # Internal: Is actor exempted from target's expiration limit policies?
      #
      # Returns a Boolean.
      def actor_exempted?(target)
        # Exemptions can only be set at Business level and inherited by orgs.
        return false if target.is_a?(Organization) && target.business.blank?

        # The business or org's business is the owner of this policy.
        exemption_config_owner = if target.is_a?(Organization)
          target.business
        elsif target.is_a?(Business)
          target
        else
          ProgrammaticAccessTokenLifetimeConfiguration.limit_enforcer_for(target).tap do |target|
            raise ArgumentError.new("unsupported target for conditional access") unless target
          end
        end

        # Business has not enabled exemptions
        return false unless ProgrammaticAccessTokenLifetimeConfiguration.exemptions_enabled_for?(T.must(exemption_config_owner), expirable_access.pat_type)

        # Actor is an enterprise admin
        T.must(exemption_config_owner).owner?(T.cast(self, AppliedIn).actor) || T.must(exemption_config_owner).billing_manager?(T.cast(self, AppliedIn).actor)
      end

      def policy_debug_logging(msg, function, options = {})
        return unless GitHub.flipper[:evaluate_pat_filter_debug_logging].enabled?
        GitHub.logger.info(
          msg,
          {
            "code.function": function,
            "gh.request_id": GitHub.context[:request_id],
             **options
          }
        )
      end

      def target_applicable_for_lifetime_policy?(target)
        T.bind(self, AppliedIn)
        return false if target == :no_target_for_conditional_access
        return true if target.instance_of?(Organization) || target.instance_of?(Business)

        if target.instance_of?(User) && target.user?
          return GitHub.enterprise? || target.is_enterprise_managed?
        end

        false
      end
    end
  end
end
