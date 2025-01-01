# typed: true
# frozen_string_literal: true

module DigitalFrontDoor
  # rubocop:disable Rails/ModuleNaming
  class NudgeConfig < T::Struct
    const :nudge_type, Symbol
    const :nudge_id, Symbol
    const :nudge_feature_flag, Symbol
    const :nudge_group, Symbol
    const :destination_key, Symbol
  end
  # rubocop:enable Rails/ModuleNaming

  module NudgeConcern
    extend ActiveSupport::Concern
    include HawaiiExperimentHelper

    sig { params(current_user: User, business: Business, key: Symbol).returns(T::Boolean) }
    def show_dfd_new_tasks_nudge?(current_user, business, key)
      config = get_dfd_new_tasks_config(key)

      eligible_for_dfd_new_tasks_nudge?(
        current_user,
        business,
        T.must(config.nudge_id),
        T.must(config.nudge_feature_flag)
      ) &&
      (
        (key == :cb && eligible_for_dfd_cb_nudge?(business)) ||
        (key == :org && eligible_for_dfd_org_nudge?(business)) ||
        (key == :repo && eligible_for_dfd_repo_nudge?(business, current_user)) ||
        (key == :code && eligible_for_dfd_code_nudge?(business, current_user)) ||
        (key == :ghas && eligible_for_dfd_ghas_nudge?(business))
      )
    end

    sig { params(current_user: User, business: Business).returns(T::Boolean) }
    def business_has_nudge_to_show?(current_user, business)
      nudge_types = [:cb, :org, :repo, :code, :ghas]

      nudge_types.any? { |type| show_dfd_new_tasks_nudge?(current_user, business, type) }
    end

    sig { params(key: Symbol).returns(NudgeConfig) }
    def get_dfd_new_tasks_config(key)
      case key
      when :cb
        NudgeConfig.new(
          nudge_type: :cb,
          nudge_id: :dfd_new_tasks_enable_cb_nudge,
          nudge_feature_flag: :dfd_new_tasks_enable_cb_nudge,
          nudge_group: :engage,
          destination_key: :dfd_new_tasks_cb_activate_cb
        )
      when :org
        NudgeConfig.new(
          nudge_type: :org,
          nudge_id: :dfd_new_tasks_create_org_nudge,
          nudge_feature_flag: :dfd_new_tasks_create_org_nudge,
          nudge_group: :engage,
          destination_key: :dfd_new_tasks_org_create_org
        )
      when :repo
        NudgeConfig.new(
          nudge_type: :repo,
          nudge_id: :dfd_new_tasks_create_repo_nudge,
          nudge_feature_flag: :dfd_new_tasks_create_repo_nudge,
          nudge_group: :engage,
          destination_key: :dfd_new_tasks_repo_create_repo
        )
      when :code
        NudgeConfig.new(
          nudge_type: :code,
          nudge_id: :dfd_new_tasks_add_code_nudge,
          nudge_feature_flag: :dfd_new_tasks_add_code_nudge,
          nudge_group: :engage,
          destination_key: :dfd_new_tasks_code_add_code
        )
      when :ghas
        NudgeConfig.new(
          nudge_type: :ghas,
          nudge_id: :dfd_new_tasks_enable_ghas_nudge, # doesnt yet exist in update notices_dependency.rb BUSINESS_NOTICES
          nudge_feature_flag: :dfd_new_tasks_enable_ghas_nudge,
          nudge_group: :engage,
          destination_key: :dfd_new_tasks_repo_enable_ghas # doesnt yet exist in click-and-redirect handler
        )
      else
        NudgeConfig.new(
          nudge_type: :unknown,
          nudge_id: :unknown,
          nudge_feature_flag: :unknown,
          nudge_group: :unknown,
          destination_key: :unknown
        )
      end
    end

    sig { params(current_user: User, business: Business, nudge_id: Symbol, nudge_feature_flag: Symbol).returns(T::Boolean) }
    def eligible_for_dfd_new_tasks_nudge?(current_user, business, nudge_id, nudge_feature_flag)
      # Make sure the feature flag is enabled
      !!(
          current_user.feature_flag_enabled?(nudge_feature_flag, default: false) &&
          # Make sure user hasn't already dismissed notice for this business
          !current_user.dismissed_business_notice?(nudge_id.to_s, business_id: business.id) &&
          # Make sure the user owns the business
          business.owner?(current_user) &&
          # DFD trial should be active
          # This is complicated due to the need to support previous enterprise account data that existed
          # when DFD was launched as a concept / the new normal
          # For clarity
          # dfd_trial? - seems to always evaluate to true if a users first step was creating a DFD trial to get to GHEC
          # no_trial_or_active_trial - Looks at trial_competion_status and at the very least evaluates to true if an enterprise is currently in a trial state. But may also evaluate to true if (we think) an enterprise was created before DFD trials were launched...
          (business.dfd_trial? && business.trial_expires_at.present? && business.trial_expires_at >= Time.current && business.no_trial_or_active_trial?)
        )
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
          .empty?
      )
    end

    sig { params(business: Business, current_user: User).returns(T::Boolean) }
    def eligible_for_dfd_repo_nudge?(business, current_user)
      user_orgs = Organization
          .includes(business_membership: [:business])
          .where(business_organization_memberships: { business_id: business.id })

      eligible_business_orgs = user_orgs.filter { |org| org.created_at + 1.day <= Time.current }

      return false if eligible_business_orgs.empty?

      has_repo = eligible_business_orgs.any? { |org| org.repositories_associated_with(current_user).any? }

      !has_repo
    end

    sig { params(business: Business, current_user: User).returns(T::Boolean) }
    def eligible_for_dfd_code_nudge?(business, current_user)
      eligible_business_orgs = Organization
        .includes(business_membership: [:business])
        .where(business_organization_memberships: { business_id: business.id })

      return false if eligible_business_orgs.empty?

      has_empty_repo = eligible_business_orgs.any? do |org|
        org.repositories_associated_with(current_user).any? { |repo| repo.created_at + 1.day <= Time.current && repo.empty? }
      end

      has_empty_repo
    end

    sig { params(business: Business).returns(T::Boolean) }
    def eligible_for_dfd_ghas_nudge?(business)
      # place holder
      false
    end
  end
end
