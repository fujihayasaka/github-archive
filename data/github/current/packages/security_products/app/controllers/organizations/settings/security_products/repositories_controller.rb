# typed: true
# frozen_string_literal: true

class Organizations::Settings::SecurityProducts::RepositoriesController < Orgs::Controller
  extend T::Sig

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include EnablementAdvancedSecurityLicenseDependency
  include EnablementSettingsDependency
  include Settings::SecurityProducts::RepositoriesHelper

  # Access
  before_action :manage_security_products_permission_required

  allow_verified_fetch only: [:index, :advanced_security_license_summary, :apply_confirmation_summary]
  before_action :parse_json_params, only: [:index, :advanced_security_license_summary, :apply_confirmation_summary]

  # allow us to render more than 100 pages of repos
  skip_before_action :cap_pagination, only: [:index, :apply_confirmation_summary], unless: :robot?

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Notify,
    ApplicationRecord::Spokes,
    ApplicationRecord::Iam,
    only: [:index]

  sig { void }
  def index
    serialized_repos = serialized_repositories(
      organization: current_organization,
      user: current_user,
      current_page: current_page,
      user_session:,
      cap_filter:,
      search_query: params[:q] || ""
    )

    render json: {
      repositories: serialized_repos[:repositories],
      pageCount: serialized_repos[:page_count],
      totalRepositoryCount: serialized_repos[:total_repository_count],
      searchResultsLimitExceeded: serialized_repos[:search_results_limit_exceeded],
    }
  end

  def advanced_security_license_summary # rubocop:todo GitHub/UseRestfulActions
    repository_ids =
      if params[:repository_ids].blank?
        if params[:query].present?
          # Find repository IDs via search query:
          find_repo_ids_by_query(query: params[:query], organization: current_organization, actor: current_user, user_session:, cap_filter:)
        end
      else
        current_organization.repositories.active.where(id: params[:repository_ids]).pluck(:id)
      end

    payload = { licenses_needed: 0, licenses_freed: 0, failedToFetchLicenses: T.let(false, T::Boolean) }
    payload.merge!(org_license_payload(current_organization)) if params[:include_license_overview]

    unless payload[:failedToFetchLicenses]
      begin
        billable_entity = AdvancedSecurityLicense.billable_entity(current_organization)
        summary = AdvancedSecurityLicense.summary(entity: T.must(billable_entity), repository_ids:)
        payload[:licenses_needed] = summary.additional_committers
        payload[:licenses_freed] = summary.unique_committers
      rescue AdvancedSecurityLicense::TurboghasError => e
        Failbot.report(e)
        payload[:failedToFetchLicenses] = true
      end
    end

    if payload[:failedToFetchLicenses]
      render json: { error: "Summary information not available" }, status: :unprocessable_entity
    else
      render json: payload
    end
  end

  def apply_confirmation_summary # rubocop:todo GitHub/UseRestfulActions
    repository_ids = \
      if params[:repository_ids].blank?
        if params[:no_configuration_only] == "true"
          all_repo_ids = current_organization.repositories.active.not_archived_scope.pluck(:id)
          ids_with_configs = RepositorySecurityConfiguration.where(repository_id: all_repo_ids).pluck(:repository_id)
          all_repo_ids - ids_with_configs
        elsif params[:query].present?
          # Find repository IDs via search query:
          find_repo_ids_by_query(query: params[:query], organization: current_organization, actor: current_user, user_session:, cap_filter:)
        else
          find_repo_ids_by_query(query: "", organization: current_organization, actor: current_user, user_session:, cap_filter:)
        end
      else
        current_organization.repositories.active.not_archived_scope.where(id: params[:repository_ids]).pluck(:id)
      end

    repo_by_public = { true => [], false => [] }
    repository_ids.each_slice(5000) do |id_batch|
      selected_repos = current_organization.repositories.active.not_archived_scope.where(id: id_batch)
      selected_repos.each do |repo|
        repo_by_public[repo.public?] << repo
      end
    end

    errors = []
    private_and_internal_repos_count_exceeding_licenses = 0

    if params[:enable_ghas]
      if current_organization.advanced_security_purchased?
        if ghas_changes_blocked_by_policy?
          errors << "blocked_by_enterprise_policy"
        elsif repo_by_public[false].length > 0
          begin
            licenses_needed = current_organization.advanced_security_license.seat_usage_increase_if_advanced_security_enabled_for_repos(repository_ids)
            if would_exceed_license_allowance?(licenses_needed)
              errors << "license_limit_exceeded"

              # When the org has _not_ gone over its license limit yet, we want to tell them how many repos that can cause them to exceed the limit (repos with > 1 additional committer required).
              # When the org _already_ went over its license limit, we will not let them enable GHAS on _any_ other private repos, even if that repo does not require
              # any additional licenses. Therefore, we don't need to fetch the number of additional licenses in this case.
              if params[:repository_ids].present? && !allowance_already_exceeded?
                succeded, result = licenses_required_for_repositories(repo_by_public[false])
                private_and_internal_repos_count_exceeding_licenses = result.count { |_, v| v > 1 } if succeded
              end
            end
          rescue AdvancedSecurityLicense::TurboghasError, Faraday::Error => e
            Failbot.report(e)
            errors << "internal_ghas_error"
          end
        end
      else
        errors << "ghas_not_purchased"
      end
    else
      licenses_needed = 0
    end

    render json: {
      total_repo_count: (repo_by_public[true].count + repo_by_public[false].count),
      public_repo_count: repo_by_public[true].count,
      private_and_internal_repo_count: repo_by_public[false].count,
      private_and_internal_repos_count_exceeding_licenses:,
      licenses_needed:,
      errors:,
    }
  end

  private

  sig { returns(T::Boolean) }
  def ghas_changes_blocked_by_policy?
    !current_organization.policy_allows_advanced_security_enablement?
  end

  sig { params(licenses_needed: Integer).returns(T::Boolean) }
  def would_exceed_license_allowance?(licenses_needed)
    return false unless current_organization.enforce_advanced_security_committers_limits?
    return false unless current_organization.advanced_security_purchased?
    return false if current_organization.advanced_security_license.unlimited_seats?
    return true if allowance_already_exceeded?
    licenses_needed > current_organization.advanced_security_license.remaining_seats
  end

  sig { returns(T::Boolean) }
  memoize def allowance_already_exceeded?
    current_organization.advanced_security_license.allowance_exceeded?
  end
end
