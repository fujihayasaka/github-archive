# typed: true
# frozen_string_literal: true

module Api::Serializer::BillingDependency
  # Creates a Hash to be serialized to JSON.
  #
  # usage_response - Usage response data.
  # options        -  Hash
  #
  # Returns a Hash if the CheckSuite exists, or nil.
  def user_usage_report_hash(usage_response, options = {})
    items = usage_response[:reportItems].map do |item|
      {
        date: Time.at(item[:usageDate]).utc.iso8601,
        product: item[:product],
        sku: item[:sku],
        quantity: item[:quantity],
        unitType: item[:unitTypeString],
        pricePerUnit: item[:pricePerUnit],
        grossAmount: item[:grossAmount],
        discountAmount: item[:discountAmount],
        netAmount: item[:netAmount],
        repositoryName: item[:repositoryName],
      }
    end

    {
      usageItems: items
    }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # usage_response - Usage response data.
  # options        -  Hash
  #
  # Returns a Hash if the CheckSuite exists, or nil.
  def usage_report_hash(usage_response, options = {})
    items = usage_response[:reportItems].map do |item|
      {
        date: Time.at(item[:usageDate]).utc.iso8601,
        product: item[:product],
        sku: item[:sku],
        quantity: item[:quantity],
        unitType: item[:unitTypeString],
        pricePerUnit: item[:pricePerUnit],
        grossAmount: item[:grossAmount],
        discountAmount: item[:discountAmount],
        netAmount: item[:netAmount],
        organizationName: item[:organizationName],
        repositoryName: item[:repositoryName],
      }
    end

    {
      usageItems: items
    }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # usage_response -  Premium requests usage response data.
  # options        -  Hash
  #
  # Returns a Hash if the CheckSuite exists, or nil.
  def premium_request_usage_report_hash(usage_response, options = {})
    time_period = {}
    if usage_response[:query][:billing_period] == BillingPlatform::Base::BillingPeriod::Yearly
      time_period[:year] = usage_response[:query][:year]
    elsif usage_response[:query][:billing_period] == BillingPlatform::Base::BillingPeriod::Monthly
      time_period[:year] = usage_response[:query][:year]
      time_period[:month] = usage_response[:query][:month]
    elsif usage_response[:query][:billing_period] == BillingPlatform::Base::BillingPeriod::Daily
      time_period[:year] = usage_response[:query][:year]
      time_period[:month] = usage_response[:query][:month]
      time_period[:day] = usage_response[:query][:day]
    end

    cost_center = nil
    if usage_response[:costCenter]
      cost_center = {
        id: usage_response[:costCenter][:costCenterKey][:uuid],
        name: usage_response[:costCenter][:name]
      }
    elsif usage_response[:query][:cost_center_id] == "none"
      cost_center = {
        id: "none",
        name: "Enterprise Only"
      }
    end

    # Determine organization value based on entity type
    organization = if usage_response[:entity].user?
      nil
    elsif usage_response[:entity].business?
      usage_response[:organization]&.display_login
    else
      usage_response[:entity].display_login
    end

    # Determine user value based on entity type
    user = if usage_response[:entity].user?
      usage_response[:entity].display_login
    else
      usage_response[:user]&.display_login
    end

    {
      timePeriod: time_period,
      enterprise: usage_response[:entity].business? ? usage_response[:entity].name : nil,
      costCenter: usage_response[:entity].business? ? cost_center : nil,
      user: user,
      organization: organization,
      product: usage_response[:query][:product],
      model: usage_response[:query][:model],
      usageItems: usage_response[:reportItems].map do |item|
        {
          product: item[:product],
          sku: item[:sku],
          model: item[:model],
          unitType: item[:unitTypeString],
          pricePerUnit: item[:pricePerUnit],
          grossQuantity: item[:grossQuantity],
          grossAmount: item[:grossAmount],
          discountQuantity: item[:discountQuantity],
          discountAmount: item[:discountAmount],
          netQuantity: item[:netQuantity],
          netAmount: item[:netAmount],
        }
      end
    }.compact
  end

  def cost_center_hash(cost_center_response, options = {})
    current_cost_center = {
      id: cost_center_response[:costCenter][:costCenterKey][:uuid],
      name: cost_center_response[:costCenter][:name],
      state: map_cost_center_state(cost_center_response[:costCenter][:costCenterState])
    }

    if cost_center_response[:costCenter].key?(:description) && cost_center_response[:costCenter][:description].present?
      current_cost_center[:description] = cost_center_response[:costCenter][:description]
    end

    # Include azure_subscription field if the cost center is associated with an Azure subscription
    target_type = cost_center_response[:costCenter][:costCenterKey][:targetType]
    target_id = cost_center_response[:costCenter][:costCenterKey][:targetId]
    if target_type == :AzureSubscription && target_id.present?
      current_cost_center[:azure_subscription] = target_id
    end

    current_cost_center[:resources] = cost_center_response[:costCenter][:resources].map do |resource|
      get_resource_values(resource)
    end

    current_cost_center
  end

  def all_cost_centers_hash(all_cost_centers_response, options = {})
    resource_ids = {
      user_ids: [], org_ids: [], repo_ids: []
    }

    #Gather all of the ids we'll need to retrieve from the databse
    all_cost_centers_response[:costCenters].each do |cost_center|
      cost_center[:resources].each do |resource|
        resource_id = resource[:id].to_i
        resource_type = resource[:type].to_s

        case resource_type
        when Billing::Platform::Api::Utils::USER_TARGET
          resource_ids[:user_ids].push(resource_id)
        when Billing::Platform::Api::Utils::ORGANIZATION_TARGET
          resource_ids[:org_ids].push(resource_id)
        when Billing::Platform::Api::Utils::REPOSITORY_TARGET
          resource_ids[:repo_ids].push(resource_id)
        end
      end
    end

    #Fetch the resource data in batches and format
    user_hash = {}
    resource_ids[:user_ids].each_slice(1000) do |user_ids|
      user_hash.merge!(User.where(id: user_ids).pluck(:id, :display_login).to_h)
    end

    org_hash = {}
    resource_ids[:org_ids].each_slice(1000) do |org_ids|
      org_hash.merge!(Organization.where(id: org_ids).pluck(:id, :display_login).to_h)
    end

    repo_hash = {}
    resource_ids[:repo_ids].each_slice(1000) do |repo_ids|
      Repository.includes(:owner).where(id: repo_ids).find_each do |repo|
        repo_hash[repo.id] = "#{repo.owner_display_login}/#{repo.name}"
      end
    end

    #hydrate the data with the resource names
    hydrated_cost_centers = all_cost_centers_response[:costCenters].map do |cost_center|
      current_cost_center = {
        id: cost_center[:costCenterKey][:uuid],
        name: cost_center[:name],
        state: map_cost_center_state(cost_center[:costCenterState])
      }

      if cost_center.key?(:description) && cost_center[:description].present?
        current_cost_center[:description] = cost_center[:description]
      end

      # Include azure_subscription field if the cost center is associated with an Azure subscription
      target_type = cost_center[:costCenterKey][:targetType]
      target_id = cost_center[:costCenterKey][:targetId]
      if target_type == :AzureSubscription && target_id.present?
        current_cost_center[:azure_subscription] = target_id
      end

      current_cost_center[:resources] = cost_center[:resources].map do |resource|
        resource_id = resource[:id].to_i
        resource_type = resource[:type].to_s
        resource_data = {
          type: resource_type,
          name: ""
        }

        case resource_type
        when Billing::Platform::Api::Utils::USER_TARGET
          resource_data[:name] = user_hash[resource_id] || ""
        when Billing::Platform::Api::Utils::ORGANIZATION_TARGET
          resource_data[:name] = org_hash[resource_id] || ""
        when Billing::Platform::Api::Utils::REPOSITORY_TARGET
          resource_data[:name] = repo_hash[resource_id] || ""
        end

        resource_data
      end

      current_cost_center
    end

    {
      costCenters: hydrated_cost_centers
    }
  end

  def get_resource_values(resource)
    data = {
      type: resource[:type],
      name: ""
    }

    resource_id = resource[:id].to_i
    resource_type = resource[:type].to_s

    case resource_type
    when Billing::Platform::Api::Utils::USER_TARGET
      user = User.find_by(id: resource_id)
      data[:name] = user.present? ? user.display_login : ""
    when Billing::Platform::Api::Utils::ORGANIZATION_TARGET
      organization = Organization.find_by(id: resource_id)
      data[:name] = organization.present? ? organization.name : ""
    when Billing::Platform::Api::Utils::REPOSITORY_TARGET
      repo = Repositories::Public.get_active_or_deleted!(resource_id)
      data[:name] = repo.present? ? "#{repo.owner_display_login}/#{repo.name}" : ""
    end

    data
  end

  sig { params(cost_center_state: T.nilable(T.any(String, Symbol))).returns(String) }
  def map_cost_center_state(cost_center_state)
    case cost_center_state&.to_s
    when "CostCenterActive", ":CostCenterActive"
      "active"
    when "CostCenterArchived", ":CostCenterArchived"
      "deleted"
    else
      "active" # Default to active if state is unknown or missing
    end
  end

  def credits_hash(credits_response, options = {})
    # Currently limited to included usage credits
    credits = credits_response[:discounts].map do |credit|
      {
        description: "Included #{get_credit_description(credit[:targets])}",
        type: "included_usage",
        target_amount: credit[:targetAmount].round(2),
        current_amount: credit[:currentAmount].round(2),
        is_fully_applied: credit[:isFullyApplied]
      }
    end

    { credits: credits }
  end

  def get_credit_description(credit_targets)
    target_ids = credit_targets.map { |target| target[:id] }

    id_mappings = {
      %w[actions_linux actions_macos actions_windows actions_linux_arm actions_windows_arm actions_linux_slim] => "Actions minutes",
      %w[git_lfs_storage] => "Git LFS storage",
      %w[git_lfs_bandwidth] => "Git LFS bandwidth",
      %w[packages_bandwidth] => "Packages data transfer",
      %w[codespaces_compute_d2 codespaces_compute_d4 codespaces_compute_d8 codespaces_compute_d16 codespaces_compute_d32] => "Codespaces core hours",
      %w[codespaces_storage codespaces_prebuild_storage] => "Codespaces storage",
      %w[actions_storage] => "Actions storage",
      %w[packages_storage] => "Packages storage"
    }

    if %w[actions_storage packages_storage].all? { |id| target_ids.include?(id) }
      return "Actions and Packages storage"
    end

    id_mappings.each do |ids, description|
      if ids.any? { |id| target_ids.include?(id) }
        return description
      end
    end

    target_ids.join(", ") # Fallback
  end
end
