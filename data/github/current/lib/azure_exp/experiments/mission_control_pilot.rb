# typed: strict
# frozen_string_literal: true

module AzureEXP
  module Experiments
    # Mission Control Agent CTA Pilot experiment.
    #
    # Smoke test of ExP's core capabilities (assignment, consistency, event emission)
    # before building the full Mission Control service.
    #
    # Experiment details:
    #   Display Name: "Mission Control Agent CTA Pilot"
    #   Namespace:    copilot_mission_control (within github/copilot)
    #   Surface:      copilot_chat
    #   Variants:     control (no CTA) / treatment (agent CTA)
    #   Allocation:   50/50 split
    #   Randomization: User ID
    #   Status:       NOT STARTED (manual trigger only)
    module MissionControlPilot
      # TAS path for the githubcopilot ExP workspace (ID: 261c2b97-0c5c-4cda-b7e1-d655cc88bb3a).
      AZURE_EXP_PATH = "exptas16/261c2b97-0c5c-4cda-b7e1-d655cc88bb3a-githubcopilot/api/v1/tas"

      NAMESPACE = "copilot_mission_control"
      SURFACE = "copilot_chat"
      EXPERIMENT_PARAMETER = "mission_control_agent_cta_pilot"
      TREATMENT_FLIGHT = "mc_pilot_t"
      CONTROL_FLIGHT = "mc_pilot_c"
      FEATURE_FLAG = :mission_control_agent_cta_pilot

      # Hydro event names — shared between publisher and subscriber to prevent drift.
      EVENT_ASSIGNMENT = "mission_control_agent_experiment.assignment"
      EVENT_EXPOSURE = "mission_control_agent_experiment.exposure"
      EVENT_PREFLIGHT_RESULT = "mission_control_agent_experiment.preflight_result"
      EVENT_PR_CREATED = "mission_control_agent_experiment.pr_created"
      EVENT_PR_REVERTED = "mission_control_agent_experiment.pr_reverted"
      EVENT_CONSENT_GIVEN = "mission_control_agent_experiment.consent_given"

      # A lightweight value object pairing variant number with its flight name.
      Variant = T.type_alias { { number: Integer, name: String } }

      TREATMENT_VARIANT = T.let({ number: 1, name: TREATMENT_FLIGHT }.freeze, Variant)
      CONTROL_VARIANT   = T.let({ number: 0, name: CONTROL_FLIGHT }.freeze, Variant)

      # Return the experiment variant for a user, encapsulating the feature-flag
      # gate and ExP assignment check in one place.
      #
      # @param user [User, nil] the user to resolve
      # @return [Variant] treatment or control variant hash
      sig { params(user: T.nilable(User)).returns(Variant) }
      def variant_for(user)
        if user &&
            user.feature_flag_enabled?(FEATURE_FLAG, default: false) &&
            in_treatment?(user)
          TREATMENT_VARIANT
        else
          CONTROL_VARIANT
        end
      end

      # Check whether a user is assigned to the treatment variant.
      #
      # @param user [User, nil] the user to check assignment for
      # @return [Boolean] true if the user is in the treatment group
      sig { params(user: T.nilable(User)).returns(T::Boolean) }
      def in_treatment?(user)
        return false unless user

        provider(user).in_group?(group_name: EXPERIMENT_PARAMETER)
      end

      # Check whether the pilot experiment is active for a user.
      # Gated behind a feature flag so we can control rollout.
      #
      # @param user [User, nil] the user to check
      # @return [Boolean] true if user is enrolled and in treatment
      sig { params(user: T.nilable(User)).returns(T::Boolean) }
      def active_for?(user)
        return false unless user
        return false unless user.feature_flag_enabled?(FEATURE_FLAG, default: false)

        treatment = in_treatment?(user)
        emit_assignment_event(user, treatment)
        treatment
      end

      # Emit a Hydro assignment event for experiment tracking.
      # Gated behind :mission_control_experiment_hydro_events feature flag.
      #
      # @param user [User] the user assigned
      # @param treatment [Boolean] whether the user is in treatment
      sig { params(user: User, treatment: T::Boolean).void }
      def emit_assignment_event(user, treatment)
        return unless user.feature_flag_enabled?(:mission_control_experiment_hydro_events, default: false)

        v = treatment ? TREATMENT_VARIANT : CONTROL_VARIANT
        has_copilot = Copilot::Public::User.new(user).has_copilot_access?
        analytics_tracking_id = user.analytics_tracking_id

        GlobalInstrumenter.instrument(EVENT_ASSIGNMENT, {
          actor_type: :ACTOR_TYPE_USER,
          actor_id: user.id,
          actor_analytics_tracking_id: analytics_tracking_id,
          experiment_name: EXPERIMENT_PARAMETER,
          variant: v[:number],
          variant_name: v[:name],
          has_copilot: has_copilot,
          assigned_at: Time.current,
        })
      end

      # Get the full variant assignments for a user in this experiment's namespace.
      # Useful for validation/debugging of ExP assignment consistency.
      #
      # @param user [User] the user to get variants for
      # @return [Hash<String, Object>] map of parameter name to assigned value
      sig { params(user: User).returns(T::Hash[String, T.untyped]) }
      def variants_for(user)
        provider(user).variants
      end

      # Validate assignment consistency: same user should get same variant across N calls.
      #
      # @param user [User] the user to validate
      # @param calls [Integer] number of calls to make (default 10)
      # @return [Hash] { consistent: Boolean, assignments: Array, user_id: Integer }
      sig { params(user: User, calls: Integer).returns(T::Hash[Symbol, T.untyped]) }
      def validate_consistency(user, calls: 10)
        assignments = calls.times.map do
          provider(user, disable_cache: true).in_group?(group_name: EXPERIMENT_PARAMETER)
        end

        {
          consistent: assignments.uniq.size == 1,
          assignments: assignments,
          user_id: user.id
        }
      end

      private

      sig { params(user: User, disable_cache: T::Boolean).returns(Beta::OverridableExpAssignmentProvider) }
      def provider(user, disable_cache: false)
        Beta::OverridableExpAssignmentProvider.new(
          participant: Beta::Participant.from_user(user),
          assignment_path: AZURE_EXP_PATH,
          namespace: NAMESPACE,
          surface: SURFACE,
          disable_cache: disable_cache || user.feature_flag_enabled?(:disable_azure_exp_cache, default: false)
        )
      end

      extend MissionControlPilot
    end
  end
end
