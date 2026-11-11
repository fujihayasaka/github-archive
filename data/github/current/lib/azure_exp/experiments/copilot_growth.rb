# typed: strict
# frozen_string_literal: true

module AzureEXP
  module Experiments
    module CopilotGrowth
      AZURE_EXP_PATH = "vscode/ab"
      COPILOT_GROWTH_NAMESPACE = "vscode"

      FREE_CCA_AA_TEST = "free_cca_aa_exp"
      FREE_CCA_AB_TEST = "free_cca_ab_exp"

      # Note: HTTP requests to fetch experiment assignments are not allowed in DB transactions
      # so we will check the cached assignment here when necessary. This should only affect configuration
      # defaults of new users and we will ensure that this is an okay workaround during the AA test

      sig { params(user: T.nilable(User), use_cache_only: T::Boolean).returns(T::Boolean) }
      def free_cca_aa_test?(user, use_cache_only: false)
        return false unless user
        exp_provider = provider(user)

        has_cache = exp_provider.has_cache?
        if use_cache_only && !has_cache
          cache_only_miss_dogstat(FREE_CCA_AA_TEST)
          return false
        end

        res = exp_provider.in_group?(group_name: FREE_CCA_AA_TEST)
        exp_request_dogstat(FREE_CCA_AA_TEST, res, use_cache_only, has_cache)
        res
      end

      sig { params(user: T.nilable(User), use_cache_only: T::Boolean).returns(T::Boolean) }
      def free_cca_ab_test?(user, use_cache_only: false)
        return false unless user
        exp_provider = provider(user)

        has_cache = exp_provider.has_cache?
        if use_cache_only && !has_cache
          cache_only_miss_dogstat(FREE_CCA_AB_TEST)
          return false
        end

        res = exp_provider.in_group?(group_name: FREE_CCA_AB_TEST)
        exp_request_dogstat(FREE_CCA_AB_TEST, res, use_cache_only, has_cache)
        res
      end

      sig { params(user: T.nilable(User), use_cache_only: T::Boolean).returns(T::Boolean) }
      def in_free_cca_experiment?(user, use_cache_only: false)
        return false unless user

        if user.feature_flag_enabled?(:copilot_coding_agent_free_users_exp_aa, default: false)
          # no-op AA test check
          free_cca_aa_test?(user, use_cache_only: use_cache_only)
        end

        return false unless user.feature_flag_enabled?(:copilot_coding_agent_free_users_exp, default: false)
        free_cca_ab_test?(user, use_cache_only: use_cache_only)
      end

      private

      sig { params(user: User).returns(Beta::OverridableExpAssignmentProvider) }
      def provider(user)
        participant = Beta::Participant.tracking_id_from_user(user)
        access_type = Copilot::User.new(user).access_type_sku

        Beta::OverridableExpAssignmentProvider.new(
          participant:,
          assignment_path: AZURE_EXP_PATH,
          namespace: COPILOT_GROWTH_NAMESPACE,
          custom_params: { "copilottrackingid" => participant.randomization_id, "copilotsku" => access_type },
          disable_cache: user.feature_flag_enabled?(:disable_azure_exp_cache, default: false)
        )
      end

      sig { params(group_name: String, in_group: T::Boolean, use_cache_only: T::Boolean, has_cache: T::Boolean).void }
      def exp_request_dogstat(group_name, in_group, use_cache_only, has_cache)
        GitHub.dogstats.increment("azure.exp.copilot_growth.#{group_name.downcase}.cache_only.hit") if use_cache_only

        GitHub.dogstats.increment("azure.exp.copilot_growth.#{group_name.downcase}.request", tags: ["in_group:#{in_group}", "use_cache_only:#{use_cache_only}", "cached:#{has_cache}"])
      end

      sig { params(group_name: String).void }
      def cache_only_miss_dogstat(group_name)
        GitHub.dogstats.increment("azure.exp.copilot_growth.#{group_name.downcase}.cache_only.miss")
      end

      extend CopilotGrowth
    end
  end
end
