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

  def cost_center_hash(cost_center_response, options = {})
    {
      id: cost_center_response[:costCenter][:costCenterKey][:uuid],
      name: cost_center_response[:costCenter][:name],
      resources: cost_center_response[:costCenter][:resources].map do |resource|
        get_resource_values(resource)
      end,
    }
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
      repo_hash.merge!(Repository.where(id: repo_ids).pluck(:id, :name).to_h)
    end

    #hydrate the data with the resource names
    hydrated_cost_centers = all_cost_centers_response[:costCenters].map do |cost_center|
      current_cost_center = {
        id: cost_center[:costCenterKey][:uuid],
        name: cost_center[:name]
      }

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
      data[:name] = repo.present? ? repo.name || "" : ""
    end

    data
  end
end
