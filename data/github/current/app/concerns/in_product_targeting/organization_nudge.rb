# typed: true
# frozen_string_literal: true

module InProductTargeting
  module OrganizationNudge
    extend ActiveSupport::Concern
    include HawaiiExperimentHelper

    sig { params(current_user: User, organization: Organization, key: Symbol).returns(T::Boolean) }
    def show_organization_tasks_nudge?(current_user, organization, key)
      configs = get_organization_tasks_configs(key)
      eligible_for_organization_tasks_nudge?(
        current_user,
        organization,
        T.must(configs[:nudge_id]),
        T.must(configs[:nudge_feature_flag])
      ) &&
      (
        key == :raf_cb && eligible_for_raf_cb_nudge?(organization)
      )
    end

    sig { params(key: Symbol).returns(T::Hash[Symbol, Symbol]) }
    def get_organization_tasks_configs(key)
      case key
      when :raf_cb
        {
          nudge_id: :organizations_new_tasks_raf_cb_nudge,
          nudge_feature_flag: :organizations_new_tasks_raf_cb_nudge,
          nudge_group: :engage
        }
      else
        {}
      end
    end

    sig { params(current_user: User).returns(Integer) }
    def get_organization_tasks_variant(current_user)
      # Get initial variant from experiment
      initial_variant = hawaii_experiment_variant(
        experiment_id: "organizations_show_new_tasks_nudges",
        user_id: current_user.id,
        variant_count: 2,
      )

      # Override variant based on feature flags
      variant = initial_variant
      variant = 0 if current_user.feature_flag_enabled?(:organizations_new_tasks_nudges_variant_0_preference, default: false)
      variant = 1 if current_user.feature_flag_enabled?(:organizations_new_tasks_nudges_variant_1_preference, default: false)

      variant
    end

    sig { params(current_user: User, organization: Organization, nudge_id: Symbol, nudge_feature_flag: Symbol).returns(T::Boolean) }
    def eligible_for_organization_tasks_nudge?(current_user, organization, nudge_id, nudge_feature_flag)
      response =
        # Make sure the feature flag is enabled
        current_user.feature_flag_enabled?(nudge_feature_flag, default: false) &&
        # Make sure user hasn't already dismissed notice for this organization
        !current_user.dismissed_organization_notice?(nudge_id.to_s, organization_id: organization.id) &&
        # Make sure the user owns the organization
        organization.adminable_by?(current_user)

      !!response
    end

    sig { params(organization: Organization).returns(T::Boolean) }
    def eligible_for_raf_cb_nudge?(organization)
      # Make sure the number of CB feature requests for this organization is greater than 0
      feature_counts = MemberFeatureRequest.total_by_feature(organization)
      copilot_for_business_count = feature_counts[MemberFeatureRequest::Feature::CopilotForBusiness] || 0
      copilot_for_business_count > 0
    end

  end
end
