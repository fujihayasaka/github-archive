# typed: strict
# frozen_string_literal: true

module AzureEXP
  module Experiments
    module MissionControlDecoupledPr
      # TAS path for the githubcopilot ExP workspace (ID: 261c2b97-0c5c-4cda-b7e1-d655cc88bb3a).
      AZURE_EXP_PATH = "exptas16/261c2b97-0c5c-4cda-b7e1-d655cc88bb3a-githubcopilot/api/v1/tas"

      NAMESPACE = "default"
      SURFACE = "mission_control"
      EXPERIMENT_PARAMETER = "mission_control_decoupled_pr"

      # TODO: Replace placeholder flight names with real ExP flight names.
      TREATMENT_FLIGHT = "mc_decoupled_pr_t"
      CONTROL_FLIGHT = "mc_decoupled_pr_c"

      FEATURE_FLAG = :mission_control_experiment_decoupled_prs
      STAFF_SHIP_FEATURE_FLAG = :mission_control_experiment_staff_exclusion

      # Feature flags to enable in Vexi for treatment users so downstream services
      # (sweagentd, CAPI) pick them up through their own Vexi checks.
      DEPENDENT_FEATURE_FLAGS = T.let([
        :copilot_mission_control_decoupled_mode,
        :coding_agent_planning_first,
        :coding_agent_create_pull_request,
      ].freeze, T::Array[Symbol])

      DEPENDENT_FLAGS_CACHE_TTL = T.let(1.day, ActiveSupport::Duration)

      EVENT_ASSIGNMENT = "mission_control_agent_experiment.assignment"
      EVENT_EXPOSURE = "mission_control_agent_experiment.exposure"

      Variant = T.type_alias { { number: Integer, name: String } }

      TREATMENT_VARIANT = T.let({ number: 1, name: TREATMENT_FLIGHT }.freeze, Variant)
      CONTROL_VARIANT = T.let({ number: 0, name: CONTROL_FLIGHT }.freeze, Variant)

      sig { params(user: T.nilable(User)).returns(T::Boolean) }
      def experiment_enabled_for?(user)
        return false unless user
        return false unless user.feature_flag_enabled?(FEATURE_FLAG, default: false)
        return false if user.feature_flag_enabled?(STAFF_SHIP_FEATURE_FLAG, default: false)

        true
      end

      sig { params(user: T.nilable(User)).returns(Variant) }
      def variant_for(user)
        if experiment_enabled_for?(user) && in_treatment?(user)
          TREATMENT_VARIANT
        else
          CONTROL_VARIANT
        end
      end

      sig { params(user: T.nilable(User)).returns(T::Boolean) }
      def in_treatment?(user)
        return false unless user

        exp_provider = provider(user)
        begin
          exp_provider.in_group?(group_name: EXPERIMENT_PARAMETER)
        rescue => e
          GitHub.logger.error("[MC_EXP] in_treatment? EXCEPTION", { "gh.user.id" => user.id, "gh.error" => "#{e.class}:#{e.message}" })
          false
        end
      end

      sig { params(user: T.nilable(User)).returns(T::Boolean) }
      def active_for?(user)
        return false unless user
        return false unless experiment_enabled_for?(user)

        treatment = in_treatment?(user)
        sync_dependent_flags(user, treatment)
        emit_assignment_event(user, treatment)
        treatment
      end

      sig { params(user: User, treatment: T::Boolean).void }
      def emit_assignment_event(user, treatment)
        return unless user.feature_flag_enabled?(:mission_control_experiment_hydro_events, default: false)

        variant = treatment ? TREATMENT_VARIANT : CONTROL_VARIANT

        GlobalInstrumenter.instrument(EVENT_ASSIGNMENT, {
          actor_type: :ACTOR_TYPE_USER,
          actor_id: user.id,
          actor_analytics_tracking_id: user.analytics_tracking_id,
          experiment_name: EXPERIMENT_PARAMETER,
          variant: variant[:number],
          variant_name: variant[:name],
          has_copilot: Copilot::Public::User.new(user).has_copilot_access?,
          assigned_at: Time.current,
        })
      end

      # Synchronise dependent Vexi feature flags with the user's treatment state.
      sig { params(user: User, treatment: T::Boolean).void }
      def sync_dependent_flags(user, treatment)
        cache_key = "mc_exp_dependent_flags_state:#{user.id}"
        desired_state = treatment ? "enabled" : "disabled"
        return if GitHub.cache.read(cache_key) == desired_state

        if treatment
          DEPENDENT_FEATURE_FLAGS.each do |flag|
            next if user.feature_flag_enabled?(flag, default: false)
            FeatureFlag.vexi_management.add_feature_flag_actors(flag, [user]) # rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage
          end
        else
          DEPENDENT_FEATURE_FLAGS.each do |flag|
            next unless user.feature_flag_enabled?(flag, default: false)
            FeatureFlag.vexi_management.remove_feature_flag_actors(flag, [user]) # rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage
          end
        end

        GitHub.cache.write(cache_key, desired_state, expires_in: DEPENDENT_FLAGS_CACHE_TTL)
      rescue => e
        GitHub.logger.error("[MC_EXP] sync_dependent_flags failed", {
          "gh.user.id" => user.id,
          "gh.treatment" => treatment,
          "gh.error" => "#{e.class}:#{e.message}",
        })
      end

      private

      sig { params(user: User, disable_cache: T::Boolean).returns(Beta::OverridableExpAssignmentProvider) }
      def provider(user, disable_cache: false)
        Beta::OverridableExpAssignmentProvider.new(
          participant: Beta::Participant.from_user(user),
          namespace: NAMESPACE,
          surface: SURFACE,
          assignment_path: AZURE_EXP_PATH,
          disable_cache: disable_cache || user.feature_flag_enabled?(:disable_azure_exp_cache, default: false),
        )
      end

      extend MissionControlDecoupledPr
    end
  end
end
