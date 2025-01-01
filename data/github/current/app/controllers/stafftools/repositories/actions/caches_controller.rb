# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::Actions::CachesController < StafftoolsController
  include ActionsCacheControllerMethods

  before_action :ensure_repo_exists

  javascript_bundle :"stafftools-repositories"
  layout "layouts/stafftools/repository/actions"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    only: [:index]

  def index
    return render_404 unless GitHub.actions_enabled?

    cache_usage = ActionsCacheUsage.get_repo_cache_usage(current_repository)
    cache_limit = ActionsCacheUsagePolicy.get_repository_cache_usage_policy(current_repository: current_repository)

    @cache_usage_gb = cache_usage_in_gb(cache_usage)
    is_over_limit = @cache_usage_gb > cache_limit

    @applied_storage_limit = ActionsPolicyHelper.get_applied_cache_storage_limit(current_repository)
    @applied_retention_limit = ActionsPolicyHelper.get_applied_cache_retention(current_repository)
    @storage_limits = ActionsPolicyHelper.get_cache_limits(current_repository)
    @retention_limits = ActionsPolicyHelper.get_cache_retention(current_repository)

    # Pre-compute percentage for view
    @cache_usage_percentage = cache_usage_percentage(@cache_usage_gb, @applied_storage_limit)

    # Get billing information
    @billing_customer_id = Billing::EntityResolver.customer_id(current_repository)
    @billing_owner = Billing::EntityResolver.billing_owner(current_repository)

    # Get watermark billing level for this repository
    @watermark_billing_level = get_watermark_billing_level

    # Calculate expected billing level and discrepancy between watermark and expected level
    @expected_billing_level = calculate_expected_billing_level(cache_usage)
    @discrepancy = check_discrepancy

    # Get can proceed with usage information
    @can_proceed_with_usage = get_can_proceed_with_usage

    caches = cache_items
    max_allowed_page = [1, (caches[:total_count] / DEFAULT_PER_PAGE.to_f).ceil].max

    if current_page > max_allowed_page
      current_page = max_allowed_page
    end
    caches = caches[:actions_caches]

    render "stafftools/repositories/actions/caches",
      locals: {
        current_repository:,
        cache_usage:,
        cache_limit:,
        is_over_limit:,
        caches:,
        applied_storage_limit: @applied_storage_limit,
        applied_retention_limit: @applied_retention_limit,
        storage_limits: @storage_limits,
        retention_limits: @retention_limits,
        cache_usage_percentage: @cache_usage_percentage,
        billing_customer_id: @billing_customer_id,
        billing_owner: @billing_owner,
        watermark_billing_level: @watermark_billing_level,
        expected_billing_level: @expected_billing_level,
        discrepancy: @discrepancy,
        can_proceed_with_usage: @can_proceed_with_usage
      }
  end

  private

  def cache_usage_in_gb(cache_usage)
    return 0.0 unless cache_usage&.active_caches_size
    (cache_usage.active_caches_size.to_f / (1024**3)).round(2)
  end

  def cache_usage_percentage(cache_usage_gb, limit)
    return 0 if limit <= 0
    ((cache_usage_gb / limit) * 100).round(1)
  end

  def check_discrepancy
    begin
      # Use watermark value directly since it's already a double
      watermark_value = @watermark_billing_level
      expected_billing_level = @expected_billing_level

      # Handle cases where watermark_billing_level might be an error string
      if watermark_value.is_a?(String)
        return "Unable to calculate discrepancy: #{watermark_value}"
      end

      return "Unable to calculate discrepancy" if watermark_value.nil? || expected_billing_level.nil?

      difference = watermark_value - expected_billing_level

      if difference > 0
        "+#{difference.round(2)} GB (watermark exceeds expected level)"
      elsif difference < 0
        "#{difference.round(2)} GB (expected level exceeds watermark)"
      else
        "0 GB (levels match)"
      end
    rescue => e
      "Error calculating discrepancy: #{e.message}"
    end
  end

  def calculate_expected_billing_level(cache_usage)
    begin
      # Use the helper method for consistent calculation
      cache_usage_gb = cache_usage_in_gb(cache_usage)

      # Calculate cache usage minus 10 GB
      cache_usage_minus_10 = [cache_usage_gb - 10, 0].max

      # Calculate applied policy minus 10 GB
      applied_policy_minus_10 = [@applied_storage_limit.to_f - 10, 0].max

      # Return the lower of the two
      [cache_usage_minus_10, applied_policy_minus_10].min
    rescue => e
      0.0 # Return 0 if there's any error in calculation
    end
  end

  def get_watermark_billing_level
    begin
      customer_id = @billing_customer_id

      return "No customer ID found" unless customer_id

      # Create the billing client
      client = Billing::Platform::Api::Client.new

      # Make the API call
      response = client.get_watermark_level(
        usage_entity_id: customer_id,
        sku: ActionsPolicyHelper::ACTIONS_CACHE_SKU,
        org_id: current_repository.owner.is_a?(Organization) ? current_repository.owner.id : nil,
        repo_id: current_repository.id
      )

      # Handle the response - return the double value directly
      if response.is_a?(Hash) && response.has_key?(:quantity)
        response[:quantity].to_f
      elsif response.is_a?(Billing::Platform::Api::Error)
        "Could not retrieve watermark level from the billing platform."
      else
        "No watermark level found"
      end
    rescue => e
      "Error retrieving watermark level: #{e.message}"
    end
  end

  def get_can_proceed_with_usage
    begin
      customer_id = @billing_customer_id
      return { billable: false, status: "No customer ID found" } unless customer_id

      # Create request params for CanProceedWithUsage
      cpwu_params = Billing::Platform::CanProceedWithUsage::RequestParams.new(
        customer_id: customer_id.to_s,
        product: "actions",
        sku: ActionsPolicyHelper::ACTIONS_CACHE_SKU,
        repo_id: current_repository.id
      )

      # Make the API call
      response = Billing::Platform::CanProceedWithUsage.call(cpwu_params)

      if response.error.present?
        { billable: false, status: "Error: #{response.error}" }
      else
        { billable: response.can_proceed, status: response.status.to_s }
      end
    rescue => e
      { billable: false, status: "Error: #{e.message}" }
    end
  end
end
