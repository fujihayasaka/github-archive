# typed: true
# frozen_string_literal: true

module DigitalFrontDoor
  module NudgeConcern
    extend ActiveSupport::Concern
    include HawaiiExperimentHelper

    sig { params(current_user: User, business: Business, key: Symbol).returns(T::Boolean) }
    def show_dfd_new_tasks_nudge?(current_user, business, key)
      configs = get_dfd_new_tasks_configs(key)
      eligible_for_dfd_new_tasks_nudge?(
        current_user,
        business,
        T.must(configs[:nudge_id]),
        T.must(configs[:nudge_feature_flag])
      ) &&
      (
        (key == :cb && eligible_for_dfd_cb_nudge?(business)) ||
        (key == :org && eligible_for_dfd_org_nudge?(business)) ||
        (key == :repo && eligible_for_dfd_repo_nudge?(business)) ||
        (key == :code && eligible_for_dfd_code_nudge?(business)) ||
        (key == :ghas && eligible_for_dfd_ghas_nudge?(business))
      )
    end

    sig { params(key: Symbol).returns(T::Hash[Symbol, Symbol]) }
    def get_dfd_new_tasks_configs(key)
      case key
      when :cb
        {
          nudge_id: :dfd_new_tasks_enable_cb_nudge,
          nudge_feature_flag: :dfd_new_tasks_enable_cb_nudge,
          nudge_group: :engage
        }
      when :org
        {
          nudge_id: :dfd_new_tasks_create_org_nudge,
          nudge_feature_flag: :dfd_new_tasks_create_org_nudge,
          nudge_group: :engage
        }
      when :repo
        {
          # dont forget to update notices_dependency.rb BUSINESS_NOTICES
          nudge_id: :dfd_new_tasks_create_repo_nudge,
          nudge_feature_flag: :dfd_new_tasks_create_repo_nudge,
          nudge_group: :engage
        }
      when :code
        {
          # dont forget to update notices_dependency.rb BUSINESS_NOTICES
          nudge_id: :dfd_new_tasks_add_code_nudge,
          nudge_feature_flag: :dfd_new_tasks_add_code_nudge,
          nudge_group: :engage
        }
      when :ghas
        {
          # dont forget to update notices_dependency.rb BUSINESS_NOTICES
          nudge_id: :dfd_new_tasks_enable_ghas_nudge,
          nudge_feature_flag: :dfd_new_tasks_enable_ghas_nudge,
          nudge_group: :engage
        }
      else
        {}
      end
    end

    sig { params(current_user: User).returns(Integer) }
    def get_dfd_new_tasks_variant(current_user)
      # Get initial variant from experiment
      initial_variant = hawaii_experiment_variant(
        experiment_id: "dfd_show_new_tasks_nudges",
        user_id: current_user.id,
        variant_count: 2,
      )

      # Override variant based on feature flags
      variant = initial_variant
      variant = 0 if current_user.feature_enabled?(:dfd_show_new_tasks_nudges_variant_0_preference)
      variant = 1 if current_user.feature_enabled?(:dfd_show_new_tasks_nudges_variant_1_preference)

      variant
    end

    sig { params(current_user: User, business: Business, nudge_id: Symbol, nudge_feature_flag: Symbol).returns(T::Boolean) }
    def eligible_for_dfd_new_tasks_nudge?(current_user, business, nudge_id, nudge_feature_flag)
      # Make sure the feature flag is enabled
      current_user.feature_enabled?(nudge_feature_flag) &&
      # Make sure user hasn't already dismissed notice for this business
      !current_user.dismissed_business_notice?(nudge_id.to_s, business_id: business.id) &&
      # Make sure the user owns the business
      business.owner?(current_user) &&
      # DFD trial should be active
      business.dfd_trial? &&
      # DFD trial should not be expired
      !business.trial_expired?
    end

    sig { params(business: Business).returns(T::Boolean) }
    def eligible_for_dfd_cb_nudge?(business)
      # DFD trial should have been active for at least 3 days
      # and must not have verified their identity for copilot access
      !!(business.created_at + 3.days <= Time.current && !business.authenticated_through_digital_front_door?)
    end

    sig { params(business: Business).returns(T::Boolean) }
    def eligible_for_dfd_org_nudge?(business)
      !!(
        business.created_at + 5.days <= Time.current &&
        Organization
          .includes(business_membership: [:business])
          .where(business_organization_memberships: { business_id: business.id })
          .count == 0
      )
    end

    sig { params(business: Business).returns(T::Boolean) }
    def eligible_for_dfd_repo_nudge?(business)
      # place holder
      false
    end

    sig { params(business: Business).returns(T::Boolean) }
    def eligible_for_dfd_code_nudge?(business)
      # place holder
      false
    end

    sig { params(business: Business).returns(T::Boolean) }
    def eligible_for_dfd_ghas_nudge?(business)
      # place holder
      false
    end
  end
end
