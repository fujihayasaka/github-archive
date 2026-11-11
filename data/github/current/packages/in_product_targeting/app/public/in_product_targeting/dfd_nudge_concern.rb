# typed: strict
# frozen_string_literal: true

module InProductTargeting

  module DfdNudgeConcern
    extend ActiveSupport::Concern
    include HawaiiExperimentHelper
    include InProductTargeting::NudgeConcern

    NudgeConfig = InProductTargeting::NudgeConcern::NudgeConfig

    sig { params(current_user: User, business: Business, key: Symbol).returns(T::Boolean) }
    def show_dfd_new_tasks_nudge?(current_user, business, key)
      config = get_dfd_new_tasks_config(key)

      eligible_for_dfd_new_tasks_nudge?(
        current_user,
        business,
        config.nudge_id,
        config.nudge_feature_flag
      ) &&
      (
        (key == :cb && eligible_for_dfd_cb_nudge?(business)) ||
        (key == :org && eligible_for_dfd_org_nudge?(business)) ||
        (key == :repo && eligible_for_dfd_repo_nudge?(business, current_user)) ||
        (key == :code && eligible_for_dfd_code_nudge?(business, current_user)) ||
        (key == :ghas && eligible_for_dfd_ghas_nudge?(business, current_user))
      )
    end

    sig { params(current_user: User, business: Business).returns(T::Boolean) }
    def business_has_dfd_nudge_to_show?(current_user, business)
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
          nudge_id: :dfd_new_tasks_enable_ghas_nudge,
          nudge_feature_flag: :dfd_new_tasks_enable_ghas_nudge,
          nudge_group: :engage,
          destination_key: :dfd_new_tasks_repo_enable_ghas
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

    sig { params(current_user: User, business: Business, nudge_id: Symbol, nudge_feature_flag: T.nilable(Symbol)).returns(T::Boolean) }
    def eligible_for_dfd_new_tasks_nudge?(current_user, business, nudge_id, nudge_feature_flag)
      # Make sure the feature flag is enabled
      !!(
          (
            nudge_feature_flag.nil? ||
            current_user.feature_flag_enabled?(nudge_feature_flag, default: false)
          ) &&
          # Make sure user hasn't already dismissed notice for this business
          !current_user.dismissed_business_notice?(nudge_id.to_s, business_id: business.id) &&
          # Make sure the user owns the business
          business.owner?(current_user) &&
          is_business_in_active_dfd_trial?(business)
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
      business_orgs = Organization
          .includes(business_membership: [:business])
          .where(business_organization_memberships: { business_id: business.id })

      return false if business_orgs.empty?

      # We might have recently created orgs that immediately added a repo,
      # in which case we don't want to show this nudge
      has_repo = business_orgs.any? { |org| org.repositories_associated_with(current_user).any? }
      return false if has_repo

      # If we don't already have a Repo created, then we only want to nudge the user
      # if they have an Org older than 1 day old
      business_orgs.any? { |org| org.created_at + 1.day <= Time.current }
    end

    sig { params(business: Business, current_user: User).returns(T::Boolean) }
    def eligible_for_dfd_code_nudge?(business, current_user)
      eligible_business_orgs = Organization
        .includes(business_membership: [:business])
        .where(business_organization_memberships: { business_id: business.id })

      return false if eligible_business_orgs.empty?

      all_repos_in_business = eligible_business_orgs.flat_map do |org|
        org.repositories_associated_with(current_user)
      end

      return false if all_repos_in_business.empty?

      all_repos_in_business.all? do |repo|
        next unless repo.created_at + 1.day <= Time.current
        repo.empty?
      end
    end

    sig { params(business: Business, current_user: User).returns(T::Boolean) }
    def eligible_for_dfd_ghas_nudge?(business, current_user)
      eligible_business_orgs = Organization
        .includes(business_membership: [:business])
        .where(business_organization_memberships: { business_id: business.id })

      return false if eligible_business_orgs.empty?

      all_repos_in_business = business.organizations.flat_map do |org|
        org.repositories
      end

      return false if all_repos_in_business.empty?

      has_repo_with_code = all_repos_in_business.any? do |repo|
        next unless repo.created_at + 24.hours <= Time.current

        # "pushed_at is set initially even for an empty repository but if it continues to be updated after a day
        # then you should know the repository has remained active (been committed to) past its creation time"
        next unless repo.created_at + 24.hours <= repo.pushed_at

        true
      end

      return false unless has_repo_with_code

      # if any repo in any org in the Enterprise has either CS or SS enabled, then we don't show the nudge
      all_repos_in_business.any? do |repo|
        return false if CodeSecurity::Features::AdvancedSecurityHelper.code_security_enabled?(repository: repo)
        return false if SecretScanning::Features::AdvancedSecurityHelper.secret_scanning_enabled?(repo)
      end

      true
    end
  end
end
