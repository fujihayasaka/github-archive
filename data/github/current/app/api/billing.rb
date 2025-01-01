# typed: true
# frozen_string_literal: true

class Api::Billing < Api::App
  MAX_NUMBER_OF_USER_RESOURCES = 500.freeze

  # Get Advanced Security billing information for organizations
  get "/organizations/:organization_id/settings/billing/advanced-security", operation_id: "billing/get-github-advanced-security-billing-org" do
    org = find_org!

    if org.business&.feature_enabled?(:saml_scope_private_resources_to_org)
      resource = Platform::InternalResource.new(resource: org)
    else
      resource = org
    end

    control_access :view_org_settings,
      resource: resource,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = Business::AdvancedSecurityCommittersGenerator.generate_json(org, page: pagination[:page], per_page: pagination[:per_page] || DEFAULT_PER_PAGE)

    deliver_raw(data)
  end

  # Get Advanced Security billing information for enterprises
  get "/enterprises/:enterprise_id/settings/billing/advanced-security", operation_id: "billing/get-github-advanced-security-billing-ghe" do
    enterprise = find_enterprise!
    control_access :manage_business_billing,
      resource: enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = Business::AdvancedSecurityCommittersGenerator.generate_json(enterprise, page: pagination[:page], per_page: pagination[:per_page] || DEFAULT_PER_PAGE)

    deliver_raw(data)
  end

  # the majority of the billing endpoints are not applicable to GHES
  unless GitHub.enterprise?
    # Get Actions billing information for users
    get "/user/:user_id/settings/billing/actions", operation_id: "billing/get-github-actions-billing-user" do
      user = find_user!
      control_access :read_user_plan,
        resource: user,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      deliver_raw(serialize_actions_usage(billable_owner: user))
    end

    # Get Actions billing information for organizations
    get "/organizations/:organization_id/settings/billing/actions", operation_id: "billing/get-github-actions-billing-org" do
      org = find_org!
      control_access :view_org_settings,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      if org.delegate_billing_to_business?
        deliver_raw(serialize_actions_usage(billable_owner: org.business, owner: org))
      else
        deliver_raw(serialize_actions_usage(billable_owner: org))
      end
    end

    # Get Actions billing information for enterprises
    get "/enterprises/:enterprise_id/settings/billing/actions", operation_id: "billing/get-github-actions-billing-ghe" do
      enterprise = find_enterprise!
      control_access :manage_business_billing,
        resource: enterprise,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      deliver_raw(serialize_actions_usage(billable_owner: enterprise))
    end

    def serialize_actions_usage(billable_owner:, owner: nil)
      account = owner || billable_owner
      actions_usage = ::Billing::ActionsUsage.product_usage(account)
      if actions_usage.has_error?
        deliver_error! 503,
          message: "Billing data for GitHub Actions is temporarily unavailable."
      end

      private_minutes_used = actions_usage.minutes_used_per_runtime.clone
      private_minutes_used.each { |key, val| private_minutes_used[key] = val.to_i }

      {
        total_minutes_used: actions_usage.total_minutes_used.to_i,
        total_paid_minutes_used: actions_usage.total_paid_minutes_used.to_i,
        included_minutes: actions_usage.included_minutes,
        minutes_used_breakdown: private_minutes_used
      }
    end

    # Get Packages billing information for users
    get "/user/:user_id/settings/billing/packages", operation_id: "billing/get-github-packages-billing-user" do
      user = find_user!
      control_access :read_user_plan,
        resource: user,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      deliver_raw(serialize_packages_usage(billable_owner: user))
    end

    # Get Packages billing information for organizations
    get "/organizations/:organization_id/settings/billing/packages", operation_id: "billing/get-github-packages-billing-org" do
      org = find_org!
      control_access :view_org_settings,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      if org.delegate_billing_to_business?
        deliver_raw(serialize_packages_usage(billable_owner: org.business, owner: org))
      else
        deliver_raw(serialize_packages_usage(billable_owner: org))
      end
    end

    # Get Packages billing information for enterprises
    get "/enterprises/:enterprise_id/settings/billing/packages", operation_id: "billing/get-github-packages-billing-ghe" do
      enterprise = find_enterprise!
      control_access :manage_business_billing,
        resource: enterprise,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      deliver_raw(serialize_packages_usage(billable_owner: enterprise))
    end

    def serialize_packages_usage(billable_owner:, owner: nil)
      account = owner || billable_owner
      packages_usage = ::Billing::PackageRegistryUsage.usage_quote(account)
      if packages_usage.has_error?
        deliver_error! 503,
          message: "Billing data for packages is temporarily unavailable."
      end
      {
        total_gigabytes_bandwidth_used: packages_usage.total_gigabytes_used,
        total_paid_gigabytes_bandwidth_used: packages_usage.billable_gigabytes,
        included_gigabytes_bandwidth: packages_usage.plan_included_bandwidth
      }
    end

    # Get shared storage billing information for shared users
    get "/user/:user_id/settings/billing/shared-storage", operation_id: "billing/get-shared-storage-billing-user" do
      user = find_user!
      control_access :read_user_plan,
        resource: user,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      deliver_raw(serialize_shared_storage_usage(billable_owner: user))
    end

    # Get shared storage billing information for shared organizations
    get "/organizations/:organization_id/settings/billing/shared-storage", operation_id: "billing/get-shared-storage-billing-org" do
      org = find_org!
      control_access :view_org_settings,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      if org.delegate_billing_to_business?
        deliver_raw(serialize_shared_storage_usage(billable_owner: org.business, owner: org))
      else
        deliver_raw(serialize_shared_storage_usage(billable_owner: org))
      end
    end

    # Get shared storage billing information for shared enterprises
    get "/enterprises/:enterprise_id/settings/billing/shared-storage", operation_id: "billing/get-shared-storage-billing-ghe" do
      enterprise = find_enterprise!
      control_access :manage_business_billing,
        resource: enterprise,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      deliver_raw(serialize_shared_storage_usage(billable_owner: enterprise))
    end

    def serialize_shared_storage_usage(billable_owner:, owner: nil)
      account = owner || billable_owner
      shared_storage_used = ::Billing::SharedStorageUsage.usage_quote(account)
      if shared_storage_used.has_error?
        deliver_error! 503,
          message: "Billing data for shared storage is temporarily unavailable."
      end
      {
        days_left_in_billing_cycle: shared_storage_used.days_left_in_billing_cycle,
        estimated_paid_storage_for_month: (shared_storage_used.estimated_monthly_paid_megabytes / 1024).to_i,
        estimated_storage_for_month: shared_storage_used.estimated_monthly_private_megabytes / 1024,
      }
    end

    get "/user/:user_id/settings/billing/usage", operation_id: "billing/get-github-billing-usage-report-user" do
      user = find_user!
      control_access :read_user_plan,
        resource: user,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      unless user&.customer&.billed_via_billing_platform?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:billing/get-github-billing-usage-report-user"])
        deliver_error! 403, message: "No access to billing usage data."
      end

      # get time period params from the URL. All fields are optional and if year
      # is omitted we default to the current year. If other fields are ommitted we use
      # the first day, first month or first hour as they will still be used to build time structs
      year = params[:year].nil? ? Time.now.utc.year : params[:year].to_i
      month = params[:month].nil? ? 1 : params[:month].to_i
      day = params[:day].nil? ? 1 : params[:day].to_i
      hour = params[:hour].nil? ? 0 : params[:hour].to_i

      new_query = {
        usage_entity_id: user.customer.id,
        year: year,
        month: month,
        day: day,
        hour: hour,
        billing_period: get_billing_period_from_params(params),
      }
      usage_response = Billing::Platform::Api::Client.new.get_usage_report(**new_query)

      if usage_response.is_a?(Billing::Platform::Api::Error)
        Failbot.report(usage_response)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/get-github-billing-usage-report-user"])
        deliver_error! 503, message: "Unable to get billing usage data."
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-github-billing-usage-report-user"])
        deliver :user_usage_report_hash, add_repo_name_to_response(usage_response)
      end
    end

    get "/enterprises/:enterprise_id/settings/billing/usage", operation_id: "billing/get-github-billing-usage-report-ghe" do
      enterprise = find_enterprise!
      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      unless enterprise.customer.billed_via_billing_platform?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:billing/get-github-billing-usage-report-ghe"])
        deliver_error! 403, message: "No access to billing usage data."
      end

      # get time period params from the URL. All fields are optional and if year
      # is omitted we default to the current year. If other fields are ommitted we use
      # the first day, first month or first hour as they will still be used to build time structs
      year = params[:year].nil? ? Time.now.utc.year : params[:year].to_i
      month = params[:month].nil? ? 1 : params[:month].to_i
      day = params[:day].nil? ? 1 : params[:day].to_i
      hour = params[:hour].nil? ? 0 : params[:hour].to_i

      # if a cost center id is passed in, we want to get usage data for that specific cost center, otherwise
      # we query a usage report for the enterprise customer
      usage_entity_id = params[:cost_center_id].nil? ? enterprise.customer_id : params[:cost_center_id]

      # Validate if cost center belongs to the enterprise customer
      unless params[:cost_center_id].nil?
        cost_center_response = Billing::Platform::Api::Client.new.get_cost_center(cost_center_key: {
          customerId: enterprise.customer_id.to_s,
          uuid: params[:cost_center_id]
        })

        if cost_center_response.is_a?(Billing::Platform::Api::Error)
          Failbot.report(cost_center_response)
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/get-github-billing-usage-report-ghe"])
          deliver_error! 503, message: "Unable to get cost center billing usage data."
        end

        if cost_center_response[:costCenter].nil?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-github-billing-usage-report-ghe"])
          deliver! :usage_report_hash, { reportItems: [] }
        end
      end

      new_query = {
        usage_entity_id: usage_entity_id,
        year: year,
        month: month,
        day: day,
        hour: hour,
        billing_period: get_billing_period_from_params(params),
      }
      usage_response = Billing::Platform::Api::Client.new.get_usage_report(**new_query)

      if usage_response.is_a?(Billing::Platform::Api::Error)
        Failbot.report(usage_response)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/get-github-billing-usage-report-ghe"])
        deliver_error! 503, message: "Unable to get billing usage data."
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-github-billing-usage-report-ghe"])
        deliver :usage_report_hash, add_org_and_repo_name_to_response(usage_response)
      end
    end

    # Get billing usage report for organizations
    get "/organizations/:organization_id/settings/billing/usage", operation_id: "billing/get-github-billing-usage-report-org" do
      org = find_org!
      control_access :view_org_settings,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      unless (org.delegate_billing_to_business? && org.business&.customer&.billed_via_billing_platform?) ||
       (!org.delegate_billing_to_business? && org.customer&.billed_via_billing_platform?)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:billing/get-github-billing-usage-report-org"])
        deliver_error! 403, message: "No access to billing usage data."
      end

      # get time period params from the URL. All fields are optional and if year
      # is omitted we default to the current year. If other fields are ommitted we use
      # the first day, first month or first hour as they will still be used to build time structs
      begin
        year = params[:year].nil? ? Time.now.utc.year : Integer(params[:year])
        month = params[:month].nil? ? 1 : Integer(params[:month])
        day = params[:day].nil? ? 1 : Integer(params[:day])
        hour = params[:hour].nil? ? 0 : Integer(params[:hour])
      rescue ArgumentError
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/get-github-billing-usage-report-org"])
        deliver_error! 400, message: "Invalid time period parameters."
      end

      usage_entity_id = org.delegate_billing_to_business? ? org.business&.customer_id : org.customer&.id

      new_query = {
        usage_entity_id: usage_entity_id,
        year: year,
        month: month,
        day: day,
        hour: hour,
        billing_period: get_billing_period_from_params(params),
        org_id: org.delegate_billing_to_business? ? org.id : nil,
      }
      usage_response = Billing::Platform::Api::Client.new.get_usage_report(**new_query)

      if usage_response.is_a?(Billing::Platform::Api::Error)
        Failbot.report(usage_response)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/get-github-billing-usage-report-org"])
        deliver_error! 503, message: "Unable to get billing usage data."
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-github-billing-usage-report-org"])
        deliver :usage_report_hash, add_org_and_repo_name_to_response(usage_response)
      end
    end

    get "/enterprises/:enterprise_id/settings/billing/cost-centers", operation_id: "billing/get-all-cost-centers" do
      enterprise = find_enterprise!
      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      # only allow access to cost center data if the customer is billed via billing platform
      unless enterprise.customer.billed_via_billing_platform?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:billing/get-all-cost-centers"])
        deliver_error! 403, message: "No access to cost center data."
      end

      all_cost_centers_response = Billing::Platform::Api::Client.new.get_all_cost_centers(customer_id: enterprise.customer_id.to_s, use_cache: true)

      if all_cost_centers_response.is_a?(Billing::Platform::Api::Error)
        Failbot.report(all_cost_centers_response)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/get-all-cost-centers"])
        deliver_error! 503, message: "Unable to get billing cost center data for all cost centers."
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-all-cost-centers"])
        deliver :all_cost_centers_hash, all_cost_centers_response
      end
    end

    get "/enterprises/:enterprise_id/settings/billing/cost-centers/:cost_center_id", operation_id: "billing/get-cost-center" do
      enterprise = find_enterprise!
      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      # only allow access to cost center data if the customer is billed via billing platform
      unless enterprise.customer.billed_via_billing_platform?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:billing/get-cost-center"])
        deliver_error! 403, message: "No access to cost center data."
      end

      cost_center_response = Billing::Platform::Api::Client.new.get_cost_center(cost_center_key: {
        customerId: enterprise.customer_id.to_s,
        uuid: params[:cost_center_id]
      })

      if cost_center_response.is_a?(Billing::Platform::Api::Error)
        Failbot.report(cost_center_response)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/get-cost-center"])
        deliver_error! 503, message: "Unable to get billing cost center data."
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-cost-center"])
        deliver :cost_center_hash, cost_center_response
      end
    end

    post "/enterprises/:enterprise_id/settings/billing/cost-centers/:cost_center_id/resource", operation_id: "billing/add-resource-to-cost-center" do
      enterprise = find_enterprise!
      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      # only allow access to cost center data if the customer is billed via billing platform
      unless enterprise.customer.billed_via_billing_platform?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:billing/add-resource-to-cost-center"])
        deliver_error! 403, message: "No access to cost center data."
      end

      data = receive_with_openapi
      user_logins = data["users"]
      user_ids = []
      enterprise_members = enterprise_members(enterprise)

      if user_logins.length > MAX_NUMBER_OF_USER_RESOURCES
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/add-resource-to-cost-center"])
        deliver_error! 400, message: "Too many users. A max of #{MAX_NUMBER_OF_USER_RESOURCES} users are allowed."
      end

      user_logins.each do |login|
        if member_id = enterprise_members[login]
          user_ids << {
            id: member_id.to_s,
            type: BillingPlatform::Base::ResourceType::User,
          }
        else
          deliver_error! 403, message: "User not part of enterprise: '#{login}'"
        end
      end
      add_resource_cost_center_response = enterprise.add_resources_to_cost_center(params[:cost_center_id], user_ids)
      if add_resource_cost_center_response.is_a?(Billing::Platform::Api::Error)
        if add_resource_cost_center_response.original_error&.code == :already_exists
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:409", "operation:billing/add-resource-to-cost-center"])
          deliver_error! 409, message: "A resource you're trying to add is already associated with a cost center."
        else
          Failbot.report(add_resource_cost_center_response)
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/add-resource-to-cost-center"])
          deliver_error! 503, message: "Unable to update billing cost center data."
        end
      end

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/add-resource-to-cost-center"])
      deliver_raw({ message: "Resources successfully added to the cost center. Resources already on a different cost center were not included." }, status: 200)
    end

    delete "/enterprises/:enterprise_id/settings/billing/cost-centers/:cost_center_id/resource", operation_id: "billing/remove-resource-from-cost-center" do
      enterprise = find_enterprise!
      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      # only allow access to cost center data if the customer is billed via billing platform
      unless enterprise.customer.billed_via_billing_platform?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:billing/remove-resource-from-cost-center"])
        deliver_error! 403, message: "No access to cost center data."
      end

      data = receive_with_openapi
      user_logins = data["users"]
      user_ids = []
      enterprise_members = enterprise_members(enterprise)

      if user_logins.length > MAX_NUMBER_OF_USER_RESOURCES
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/add-resource-to-cost-center"])
        deliver_error! 400, message: "Too many users. A max of #{MAX_NUMBER_OF_USER_RESOURCES} users are allowed."
      end

      user_logins.each do |login|
        if member_id = enterprise_members[login]
          user_ids << {
            id: member_id.to_s,
            type: BillingPlatform::Base::ResourceType::User,
          }
        else
          deliver_error! 403, message: "User not part of enterprise: '#{login}'"
        end
      end
      remove_resource_cost_center_response = enterprise.remove_resources_from_cost_center(params[:cost_center_id], user_ids)
      if remove_resource_cost_center_response.is_a?(Billing::Platform::Api::Error)
        Failbot.report(remove_resource_cost_center_response)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/remove-resource-from-cost-center"])
        deliver_error! 503, message: "Unable to update billing cost center data."
      end

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/remove-resource-from-cost-center"])
      deliver_raw({ message: "Resources successfully removed from the cost center." }, status: 200)
    end

    def add_repo_name_to_response(usage_response)
      repo_ids = usage_response[:reportItems].map { |item| item[:repoID] }.uniq

      repos = Repository.select(:id, :name).where(id: repo_ids)

      repositories = repos.map do |repo|
        [repo.id, repo]
      end.to_h

      usage_response[:reportItems].each do |item|
        repository = repositories[item[:repoID]]

        item[:repositoryName] = repository&.name || ""
      end
      usage_response
    end

    def add_org_and_repo_name_to_response(usage_response)
      repo_ids = usage_response[:reportItems].map { |item| item[:repoID] }.uniq
      org_ids = usage_response[:reportItems].map { |item| item[:orgID] }.uniq

      repos = Repository.select(:id, :name).where(id: repo_ids)
      orgs = Organization.select(:id, :display_login).where(id: org_ids)

      organizations = orgs.map do |org|
        [org.id, org]
      end.to_h

      repositories = repos.map do |repo|
        [repo.id, repo]
      end.to_h

      usage_response[:reportItems].each do |item|
        repository = repositories[item[:repoID]]
        organization = organizations[item[:orgID]]

        item[:repositoryName] = repository&.name || ""
        item[:organizationName] = organization&.display_login || ""
      end
      usage_response
    end

    # choose billing period based on input params
    # e.g. if just year and month is present, we want to choose a monthly billing period
    def get_billing_period_from_params(params)
      billing_period = BillingPlatform::Base::BillingPeriod::Yearly

      if !params[:year].nil? && params[:month].nil? && params[:day].nil? && params[:hour].nil?
        billing_period = BillingPlatform::Base::BillingPeriod::Yearly
      elsif !params[:year].nil? && !params[:month].nil? && params[:day].nil? && params[:hour].nil?
        billing_period = BillingPlatform::Base::BillingPeriod::Monthly
      elsif !params[:year].nil? && !params[:month].nil? && !params[:day].nil? && params[:hour].nil?
        billing_period = BillingPlatform::Base::BillingPeriod::Daily
      elsif !params[:year].nil? && !params[:month].nil? && !params[:day].nil? && !params[:hour].nil?
        billing_period = BillingPlatform::Base::BillingPeriod::Hourly
      end

      billing_period
    end

    def enterprise_members(enterprise)
      members = Hash.new

      enterprise.admins
        .each do |user|
          members[user.display_login] = user.id
        end

      enterprise.filtered_members(current_user, ignore_org_membership_visibility: true)
        .includes(:user)
        .where.not(user_id: nil)
        .each do |member|
          members[member.user&.display_login] = member.user&.id
        end

      enterprise.filtered_outside_collaborators
        .each do |user|
          members[user.display_login] = user.id
        end

      # De-provisioned EMU users are suspended and don't show up in filtered_members
      # but need to be included in the list of users that can be removed from a cost center
      suspended_members = enterprise.suspended_members
      if suspended_members.present?
        suspended_members
          .each do |user|
            members[user.display_login] = user.id
          end
      end


      enterprise.pending_admin_invitations
        .where.not(invitee_id: nil)
        .each do |invitation|
          members[invitation.invitee&.display_login] = invitation.invitee&.id
        end

      enterprise.pending_member_invitations
        .where.not(invitee_id: nil)
        .each do |invitation|
          members[invitation.invitee&.display_login] = invitation.invitee&.id
        end

      members.compact
    end
  end
end
