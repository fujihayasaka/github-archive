# typed: true
# frozen_string_literal: true

class Organizations::Settings::SecurityProducts::RepositoriesController < Orgs::Controller
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include EnablementAdvancedSecurityLicenseDependency
  include EnablementSettingsDependency
  include SecurityConfigurations::RepositoriesDependency

  # Access
  before_action :manage_security_products_permission_required

  allow_verified_fetch only: [:index, :advanced_security_license_summary, :apply_confirmation_summary]
  before_action :parse_json_params, only: [:index, :advanced_security_license_summary, :apply_confirmation_summary]

  # allow us to render more than 100 pages of repos
  skip_before_action :cap_pagination, only: [:index, :apply_confirmation_summary], unless: :robot?

  CostEstimate = T.type_alias { T::Hash[Symbol, T::Hash[Symbol, Integer]] }

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
    search_query = params[:q] || ""

    serialized_repos = serialized_repositories(
      organization: current_organization,
      user: current_user,
      current_page: current_page,
      user_session:,
      cap_filter:,
      search_query:,
    )

    if search_query.present?
      repo_query = Search::Queries::SecurityConfigurations::RepositoryQuery.new(query: search_query, include_archived_repos: true)

      # Sends Elastic Search keyword usage analytics
      es_keys = repo_query.es_query_string.scan(/\b[\w.]+(?=:)/) - %w(sort archived)
      send_analytics_events(es_keys)

      # Sends MySQL keyword usage analytics
      mysql_keys = repo_query.mysql_query_hash.keys
      advanced_filters = repo_query.mysql_query_hash["advanced_filters"]

      if advanced_filters.present?
        mysql_keys += advanced_filters.split.map { |pair| pair.split(":").first }
      end

      send_analytics_events(mysql_keys)
    end

    render json: {
      repositories: serialized_repos[:repositories],
      pageCount: serialized_repos[:page_count],
      totalRepositoryCount: serialized_repos[:total_repository_count],
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
        base_repo_scope.where(id: params[:repository_ids]).pluck(:id)
      end

    payload = { licenses_needed: 0, licenses_freed: 0, failedToFetchLicenses: T.let(false, T::Boolean) }
    payload.merge!(org_license_payload(current_organization)) if params[:include_license_overview]

    unless payload[:failedToFetchLicenses]
      begin
        billable_entity = if repository_ids.nil?
          # When we are querying for ALL repos in an org, we want a summary for the org directly and not its owner.
          #
          # This ensures that we don't find the licenses_needed for ALL repos in the Business which owns the org.
          current_organization
        else
          # When we are filtering to certain repos, we want a summary for the billable entity and not the org.
          #
          # This ensures that the licenses_needed match the repo table, since the standalone
          # `additional_committers_per_repository` TurboGHAS call (used to populate the repos list) will automatically
          # find the billable entity, whereas the summary call will directly pass whatever entity is provided.
          AdvancedSecurityLicense.billable_entity(current_organization)
        end

        summary = AdvancedSecurityLicense.summary(entity: T.must(billable_entity), repository_ids:, sku: GitHub::Turboghas::SKU::Bundled)
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
    security_configuration = SecurityConfiguration.where(
      target: [current_organization, current_organization.business].compact,
      id: params[:id]
    ).or(SecurityConfiguration.where(target_type: "global", id: params[:id])).first
    return render_404 if security_configuration.nil?

    repository_ids = \
      if params[:repository_ids].blank?
        # Find repository IDs via search query first
        if params[:query].present?
          find_repo_ids_by_query(query: params[:query], organization: current_organization, actor: current_user, user_session:, cap_filter:)
        elsif params[:override_existing_config]
          # Applying to "All repositories" or Applying through repos table without a query
          current_organization.visible_repositories_for(current_user, batched: true).where(owner_id: current_organization.id).pluck(:id)
        else
          # Applying to "All repositories without configuration"
          all_repo_ids = base_repo_scope.pluck(:id)
          ids_with_configs = RepositorySecurityConfiguration.where(repository_id: all_repo_ids).pluck(:repository_id)
          all_repo_ids - ids_with_configs
        end
      else
        base_repo_scope.where(id: params[:repository_ids]).pluck(:id)
      end

    public_repo_ids = T.let([], T::Array[Integer])
    private_repo_ids = T.let([], T::Array[Integer])

    repository_ids.each_slice(5000) do |id_batch|
      # TODO: we could optimize this by using a single query to determine the public/private status of the repos
      selected_repos = base_repo_scope.where(id: id_batch)
      selected_repos.each do |repo|
        if repo.public?
          public_repo_ids << repo.id
        else
          private_repo_ids << repo.id
        end
      end
    end

    errors = []
    private_and_internal_repos_count_exceeding_licenses = 0
    licenses_needed = 0
    code_scanning_licenses_needed, code_scanning_licenses_missing = 0, 0
    secret_scanning_licenses_needed, secret_scanning_licenses_missing = 0, 0
    bundled = current_organization.advanced_security_license.billable_entity&.advanced_security_products_bundled?
    cost_estimate = nil

    if security_configuration.enables_paid_features?
      # If the customer has unbundled GHAS, set a default cost estimate to be used for public repos:
      cost_estimate = { total: { licenses: 0, cost: "$0.00" } } unless bundled

      if current_organization.advanced_security_purchased?
        blocked_by_policy, policy_error = ghas_changes_blocked_by_policy?(security_configuration)
        if blocked_by_policy
          errors << policy_error
        elsif private_repo_ids.length > 0
          begin
            if bundled
              res = bundled_licenses_needed(repository_ids:, private_repo_ids:)
              errors.concat(res[:errors])
              licenses_needed = res[:licenses_needed]

              if res[:private_and_internal_repos_count_exceeding_licenses]
                private_and_internal_repos_count_exceeding_licenses = res[:private_and_internal_repos_count_exceeding_licenses]
              end
            else
              res = split_licenses_needed(
                repository_ids:,
                code_security_sku_enabled: security_configuration.code_security_sku_enabled(billable_entity: current_organization),
                secret_protection_sku_enabled: security_configuration.secret_protection_sku_enabled(billable_entity: current_organization),
              )
              errors.concat(res[:errors])
              code_scanning_licenses_needed = res[:code_security_licenses_needed]
              code_scanning_licenses_missing = res[:code_security_licenses_missing]
              secret_scanning_licenses_needed = res[:secret_scanning_licenses_needed]
              secret_scanning_licenses_missing = res[:secret_scanning_licenses_missing]
              cost_estimate = res[:cost_estimate]
            end
          rescue AdvancedSecurityLicense::TurboghasError, Faraday::Error => e
            Failbot.report(e)
            errors << "internal_ghas_error"
          end
        end
      else
        errors << "ghas_not_purchased"
      end
    end

    render json: {
      total_repo_count: (public_repo_ids.count + private_repo_ids.count),
      public_repo_count: public_repo_ids.count,
      private_and_internal_repo_count: private_repo_ids.count,
      private_and_internal_repos_count_exceeding_licenses:,
      uses_action_minutes: security_configuration.uses_action_minutes?,
      bundled:,
      licenses_needed:,
      code_scanning_licenses_needed:,
      code_scanning_licenses_missing:,
      secret_scanning_licenses_needed:,
      secret_scanning_licenses_missing:,
      cost_estimate:,
      errors:,
    }
  end

  private

  sig { params(config: SecurityConfiguration).returns([T::Boolean, String]) }
  def ghas_changes_blocked_by_policy?(config)
    if config.enable_ghas?
      return [
        !current_organization.policy_allows_advanced_security_enablement?(sku: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_ALL),
        "blocked_by_enterprise_policy"
      ]
    elsif config.code_security_sku_enabled? && config.secret_protection_sku_enabled?
      cs_blocked = !current_organization.policy_allows_advanced_security_enablement?(sku: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_CODE_SECURITY_ONLY)
      sp_blocked = !current_organization.policy_allows_advanced_security_enablement?(sku: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_SECRET_PROTECTION_ONLY)

      return [false, ""] unless cs_blocked || sp_blocked
      return [true, "blocked_by_enterprise_policy"] if cs_blocked && sp_blocked
      return [true, "code_security_blocked_by_enterprise_policy"] if cs_blocked
      return [true, "secret_protection_blocked_by_enterprise_policy"] if sp_blocked
    elsif config.code_security_sku_enabled?
      return [
        !current_organization.policy_allows_advanced_security_enablement?(sku: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_CODE_SECURITY_ONLY),
        "code_security_blocked_by_enterprise_policy"
      ]
    elsif config.secret_protection_sku_enabled?
      return [
        !current_organization.policy_allows_advanced_security_enablement?(sku: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_SECRET_PROTECTION_ONLY),
        "secret_protection_blocked_by_enterprise_policy"
      ]
    end

    [false, ""]
  end

  sig { params(licenses_needed: Integer).returns(T::Boolean) }
  def would_exceed_license_allowance?(licenses_needed)
    return false unless current_organization.enforce_advanced_security_committers_limits?
    return false unless current_organization.advanced_security_purchased?
    return false if current_organization.advanced_security_license.unlimited_seats?
    licenses_needed > current_organization.advanced_security_license.remaining_seats
  end

  def send_analytics_events(keys)
    keys.each do |key|
      analytics_event(
        category: "configs_filter",
        action: key,
        label: "org_id:#{current_organization.id};user:#{current_user}"
      )
    end
  end

  memoize def base_repo_scope
    current_organization.repositories.active
  end

  sig { params(repository_ids: T::Array[Integer], private_repo_ids: T::Array[Integer]).returns(T::Hash[Symbol, T.untyped]) }
  def bundled_licenses_needed(repository_ids:, private_repo_ids:)
    licenses_needed = current_organization.advanced_security_license.seat_usage_increase_if_advanced_security_enabled_for_repos(repository_ids)
    allowance_exceeded = current_organization.advanced_security_license.allowance_exceeded?
    if allowance_exceeded || would_exceed_license_allowance?(licenses_needed)
      errors = ["license_limit_exceeded"]

      # When the org has _not_ gone over its license limit yet, we want to tell them how many repos that can cause them to exceed the limit (repos with > 1 additional committer required).
      # When the org _already_ went over its license limit, we will not let them enable GHAS on _any_ other private repos, even if that repo does not require
      # any additional licenses. Therefore, we don't need to fetch the number of additional licenses in this case.
      if params[:repository_ids].present? && !allowance_exceeded
        succeded, result = bundled_licenses_required_for_repositories(current_organization, private_repo_ids)
        private_and_internal_repos_count_exceeding_licenses = result.count { |_, v| v > 1 } if succeded
      end
    end

    { licenses_needed:, private_and_internal_repos_count_exceeding_licenses:, errors: errors || [] }
  end

  sig { params(new_code_security_licenses: T.nilable(Integer), new_secret_protection_licenses: T.nilable(Integer)).returns(T.nilable(CostEstimate)) }
  def calculate_cost_estimate(new_code_security_licenses:, new_secret_protection_licenses:)
    return if current_organization.business.present? # We don't return cost estimates for biz orgs, only team orgs.

    advanced_security_license = current_organization.advanced_security_license

    # If either of the count of new licenses is nil, we will not calculate the corresponding amount:
    calculate_code_security = current_organization.code_security_purchased? && new_code_security_licenses.is_a?(Integer)
    calculate_secret_protection = current_organization.secret_protection_purchased_for_entity? && new_secret_protection_licenses.is_a?(Integer)

    code_security_cost = if calculate_code_security
      current_organization.advanced_security_price_for_sku(sku: "ghas_code_security_licenses", seats: new_code_security_licenses)
    else
      Billing::Money.new(0)
    end

    secret_protection_cost = if calculate_secret_protection
      current_organization.advanced_security_price_for_sku(sku: "ghas_secret_protection_licenses", seats: new_secret_protection_licenses)
    else
      Billing::Money.new(0)
    end

    result = T.let({
      total: {
        licenses: (new_code_security_licenses || 0) + (new_secret_protection_licenses || 0),
        cost: (code_security_cost + secret_protection_cost).format
      },
    }, CostEstimate)

    # Add results individually, so we can exclude SKUs that aren't purchased:
    result[:code_security] = { seat_count: new_code_security_licenses, total_cost: code_security_cost.format } if calculate_code_security
    result[:secret_protection] = { seat_count: new_secret_protection_licenses, total_cost: secret_protection_cost.format } if calculate_secret_protection

    result
  end

  sig { params(repository_ids: T::Array[Integer], code_security_sku_enabled: T::Boolean, secret_protection_sku_enabled: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
  def split_licenses_needed(repository_ids:, code_security_sku_enabled:, secret_protection_sku_enabled:)
    code_security = current_organization.code_security
    secret_protection = current_organization.secret_protection

    code_security_licenses_needed = code_security_sku_enabled ? code_security.seat_usage_increase_if_enabled_for_repos(repository_ids) : nil
    secret_scanning_licenses_needed = secret_protection_sku_enabled ? secret_protection.seat_usage_increase_if_enabled_for_repos(repository_ids) : nil

    errors = []
    if code_security_sku_enabled && code_security.purchased?
      errors.append("code_security_license_limit_exceeded") if code_security.allowance_exceeded?

      if !code_security.unlimited_seats? && (code_security_licenses_needed > code_security.remaining_seats)
        code_security_licenses_missing = [0, code_security_licenses_needed - code_security.remaining_seats].max
        errors.append("applying_will_exceed_code_security_license_limit")
      end
    end

    if secret_protection_sku_enabled && secret_protection.purchased?
      errors.append("secret_protection_license_limit_exceeded") if secret_protection.allowance_exceeded?

      if !secret_protection.unlimited_seats? && (secret_scanning_licenses_needed > secret_protection.remaining_seats)
        secret_scanning_licenses_missing = [0, secret_scanning_licenses_needed - secret_protection.remaining_seats].max
        errors.append("applying_will_exceed_secret_protection_license_limit")
      end
    end

    cost_estimate = calculate_cost_estimate(
      new_code_security_licenses: code_security_licenses_needed,
      new_secret_protection_licenses: secret_scanning_licenses_needed,
    )

    {
      code_security_licenses_needed:,    # How many *total* licenses are needed to apply?
      code_security_licenses_missing:,   # How many *additional* licenses are needed to apply? Can be 0.
      secret_scanning_licenses_needed:,  # How many *total* licenses are needed to apply?
      secret_scanning_licenses_missing:, # How many *additional* licenses are needed to apply? Can be 0.
      cost_estimate:,
      errors: errors
    }
  end
end
