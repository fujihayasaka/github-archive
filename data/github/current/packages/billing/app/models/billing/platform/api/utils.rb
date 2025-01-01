# typed: true
# frozen_string_literal: true

module Billing
  module Platform
    module Api
      module Utils
        CUSTOMER_TARGET = "CustomerResource"
        USER_TARGET = "User"
        ENTERPRISE_TARGET = "Enterprise"
        ORGANIZATION_TARGET = "Org"
        REPOSITORY_TARGET = "Repo"
        COSTCENTER_TARGET = "CostCenterResource"

        CHECK_CAN_PROCEED_WITH_USAGE_BY_REASON = {
          BUDGET_SET_ZERO_HARD_LIMIT: false,
          BUDGET_UPDATED_HARD_LIMIT: true,
          BUDGET_SET_ZERO_SOFT_LIMIT: false,
          BUDGET_UPDATED_SOFT_LIMIT: false,
          BUDGET_DELETED: false,
          BUDGET_EXHAUSTED: false,
          UNKNOWN_REASON: true
        }.freeze

        def get_target_entity_from_id(target_type:, target_id:)
          case target_type
          when CUSTOMER_TARGET, ENTERPRISE_TARGET # remove enterprise when we remove enterprise budgets
            Customer.find_by(id: target_id)
          when REPOSITORY_TARGET
            if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
              T.cast(Repositories.domain.by_id(target_id.to_i), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
            else
              Repository.find_by(id: target_id)
            end
          when ORGANIZATION_TARGET
            Organization.find_by(id: target_id)
          when USER_TARGET
            User.find_by(id: target_id)
          when COSTCENTER_TARGET
            target_id
          end
        end

        def targets_owned_by_user?(target_type:, target_ids:, current_user:, this_entity:)
          return true if current_user == User.ghost

          # ensure ids are converted to ints for comparison
          target_ids.replace target_ids.map(&:to_i)
          case target_type
          when CUSTOMER_TARGET, ENTERPRISE_TARGET # remove enterprise when we remove enterprise budgets
            if this_entity.is_a?(Business)
              this_entity.owner?(current_user) || this_entity.billing_manager?(current_user)
            else
              org_admin_or_billing_manager?(entity: this_entity, current_user: current_user)
            end
          when ORGANIZATION_TARGET
            return true if this_entity.is_a?(Organization)
            if this_entity.is_a?(Business)
              owned_business_org_ids = current_user.owned_organization_ids & this_entity.organization_ids
              return owned_business_org_ids.to_set.superset?(target_ids.to_set) unless this_entity.owner?(current_user) || this_entity.billing_manager?(current_user)
            end

            return false unless this_entity.owner?(current_user) || this_entity.billing_manager?(current_user)
            this_entity.organizations.where(id: target_ids).count == target_ids.size
          when REPOSITORY_TARGET
            if this_entity.is_a?(Business)
              owned_business_org_ids = current_user.owned_organization_ids & this_entity.organization_ids
              Repository.where(organization_id: owned_business_org_ids, id: target_ids).count == target_ids.size
            elsif this_entity.is_a?(Organization)
              org_admin_or_billing_manager?(entity: this_entity, current_user: current_user) && Repository.where(organization_id: this_entity, id: target_ids).count == target_ids.size
            elsif this_entity.is_a?(User)
              Repository.where(id: target_ids, owner_id: current_user.id).count == target_ids.size
            end
          when USER_TARGET
            this_entity.is_a?(Business) # user picker already picks users that are in the business
          when COSTCENTER_TARGET
            true
          end
        end

        def filter_budget_by_role(budgets:, current_user:, entity:)
          non_repo_budgets = budgets.filter { |budget| budget[:budget][:key][:targetType].to_s != REPOSITORY_TARGET }

          if entity.is_a?(Business) && (entity.user_is_owner_of_owned_org?(current_user) || entity.billing_manager?(current_user) || entity.owner?(current_user))
            repo_ids = budgets.filter { |budget| budget[:budget][:key][:targetType].to_s == REPOSITORY_TARGET }.map { |budget| budget[:budget][:key][:targetId] }.uniq.compact
            target_repo_ids = current_user.associated_repository_ids(repository_ids: repo_ids)
            repo_budgets = budgets.filter do |budget|
              target_repo_ids.include?(budget[:budget][:key][:targetId].to_i) && budget[:budget][:key][:targetType].to_s == REPOSITORY_TARGET
            end

            target_org_ids = current_user.owned_organization_ids
            org_budgets = budgets.filter do |budget|
              target_org_ids.include?(budget[:budget][:key][:targetId].to_i) && budget[:budget][:key][:targetType].to_s == ORGANIZATION_TARGET
            end

            if entity.owner?(current_user) || entity.billing_manager?(current_user)
              budgets = budgets
            elsif entity.user_is_owner_of_owned_org?(current_user)
              budgets = (repo_budgets + org_budgets).uniq
            else
              budgets = repo_budgets
            end
          elsif entity.is_a?(Organization) && org_admin_or_billing_manager?(entity: entity, current_user: current_user)
            budgets = budgets
          else
            budgets = non_repo_budgets
          end
          budgets
        end

        def filter_repo_usage_by_ownership(usages:, current_user:, entity:)
          if entity.is_a?(Business) && (entity.billing_manager?(current_user) || entity.owner?(current_user))
            usages
          elsif entity.is_a?(Organization) && org_admin_or_billing_manager?(entity: entity, current_user: current_user)
            usages
          else
            if entity.feature_flag_enabled?(:should_not_filter_usage_by_ownership, default: false)
              usages
            else
              org_ids = current_user.owned_organization_ids
              usages = usages.filter { |item| org_ids.include?(item[:orgId]) }

              repo_ids = usages.map { |item| item[:repoId] }
              owned_repos = current_user.associated_repository_ids(repository_ids: repo_ids, include_indirect_forks: false)
              usages = usages.filter { |item| owned_repos.include?(item[:repoId]) }
              usages
            end
          end
        end

        def org_admin_or_billing_manager?(entity:, current_user:)
          entity.adminable_by?(current_user) || entity.billing_manager?(current_user)
        end

        def filter_usage_by_query(usages:, query:)
          if query[:org_id]
            usages = usages.filter { |item| item[:orgId] == query[:org_id] }
          elsif query[:repo_id]
            usages = usages.filter { |item| item[:repoId] == query[:repo_id] }
          elsif query[:product]
            usages = usages.filter { |item| item[:product] == query[:product] }
          elsif query[:sku]
            usages = usages.filter { |item| item[:sku] == query[:sku] }
          end
          usages
        end

        def json_billing_items(billing_items)
          return [] if billing_items.nil?

          billing_items.map { |item| Billing::Platform::Api::NetUsageLineItem.new(item).to_json }
        end

        def json_other_billing_items(billing_items)
          return [] if billing_items.nil?

          billing_items.map do |item|
            Billing::Platform::Api::OtherUsageLineItem.new(item).to_json
          end.compact
        end

        def json_org_repo_billing_items(billing_items, group_by)
          return [] if billing_items.nil?

          repo_ids = billing_items.map { |item| item[:repoId] }.uniq
          org_ids = billing_items.map { |item| item[:orgId] }.uniq

          organizations = Organization.where(id: org_ids).map do |org|
            [org.id, org]
          end.to_h

          repositories = Repository.includes(:owner).where(id: repo_ids).map do |repo|
            [repo.id, repo]
          end.to_h

          billing_items.map do |item|
            repo = repositories[item[:repoId]]
            org = organizations[item[:orgId]]

            # In the odd case that we do not have an organization but we do have a repository,
            # we should try to get the organization from the repository owner.
            # This is currently necessary due to packages_storage emisions not including an orgId
            # but including a repoId.
            if !org.present? && repo.present?
              org = repo.owner
            end

            if group_by == BillingPlatform::Base::UsageGroupBy::GroupByRepository
              # if we are grouping by repository we only want to return a line item if repo is present
              # since some SKUs can be included in the organization groupings that do not have repo ID attached (e.g. Copilot)
              Billing::Platform::Api::RepoUsageLineItem.new(item, org, repo).to_json if repo.present?
            else
              # if we are grouping by organization we only want to return a line item if org is present
              # since some SKUs can be included in the organization groupings that do not have org ID attached (e.g. GHEC)
              Billing::Platform::Api::RepoUsageLineItem.new(item, org, repo).to_json if org.present?
            end
          end.compact
        end

        # determine if the incoming usage request is for organization or repository data usage data
        def org_or_repo_request?(query)
          query[:group_by] == BillingPlatform::Base::UsageGroupBy::GroupByOrganization ||
          query[:group_by] == BillingPlatform::Base::UsageGroupBy::GroupByRepository ||
          query[:org_id].present? ||
          query[:repo_id].present?
        end

        def should_filter_usage_for_business?(entity, current_user)
          if entity.is_a?(Business)
            should_filter_for_org_admin?(entity, current_user)
          else
            false
          end
        end

        def should_filter_for_org_admin?(entity, current_user)
          return false unless entity.is_a?(Business)
          # do not filter billing manager or business owner usage
          !entity.billing_manager?(current_user) && !entity.owner?(current_user)
        end

        def get_org_ids_for_org_admin(entity, current_user)
          return [] unless entity.is_a?(Business)
          current_user&.owned_organization_ids & entity.organization_ids
        end

        sig { params(pricing_target_id: T.nilable(String), pricing_target_type: T.nilable(String), entity: T.any(User, Business), customer_id: String, reason_type: T.nilable(Symbol)).void }
        def publish_budget_changed_notification(pricing_target_id, pricing_target_type, entity, customer_id, reason_type)
          return if !pricing_target_id&.starts_with?("copilot")

          pricing_target_type_sym = get_pricing_target_type(pricing_target_type)
          message = {
            customer_id: customer_id,
            check_can_proceed_with_usage: check_can_proceed_with_usage(reason_type),
            reason_type: reason_type,
            pricing_target: { pricing_target_id: pricing_target_id, pricing_target_type: pricing_target_type_sym }
          }

          result = Hydro::PublishRetrier.publish(message, schema: "billingplatform.v1.BudgetChangedNotification", publisher: GitHub.hydro_publisher)

        end

        sig { params(create_budget_request: Billing::Platform::Api::UpsertBudgetRequest).returns(T.nilable(Symbol)) }
        def reason_type(create_budget_request)
          case
          when create_budget_request.budget_limit_type == "PreventFurtherUsage" && create_budget_request.target_amount.to_i == 0
            Hydro::Schemas::Billingplatform::V1::Entities::ReasonType.lookup(Hydro::Schemas::Billingplatform::V1::Entities::ReasonType::BUDGET_SET_ZERO_HARD_LIMIT)
          when create_budget_request.budget_limit_type == "PreventFurtherUsage" && create_budget_request.target_amount.to_i > 0
            Hydro::Schemas::Billingplatform::V1::Entities::ReasonType.lookup(Hydro::Schemas::Billingplatform::V1::Entities::ReasonType::BUDGET_UPDATED_HARD_LIMIT)
          when create_budget_request.budget_limit_type == "AlertingOnly" && create_budget_request.target_amount.to_i == 0
            Hydro::Schemas::Billingplatform::V1::Entities::ReasonType.lookup(Hydro::Schemas::Billingplatform::V1::Entities::ReasonType::BUDGET_SET_ZERO_SOFT_LIMIT)
          when create_budget_request.budget_limit_type == "AlertingOnly" && create_budget_request.target_amount.to_i > 0
            Hydro::Schemas::Billingplatform::V1::Entities::ReasonType.lookup(Hydro::Schemas::Billingplatform::V1::Entities::ReasonType::BUDGET_UPDATED_SOFT_LIMIT)
          else
            Hydro::Schemas::Billingplatform::V1::Entities::ReasonType.lookup(Hydro::Schemas::Billingplatform::V1::Entities::ReasonType::UNKNOWN_REASON)
          end
        end

        sig { params(pricing_target_type: T.nilable(String)).returns(T.nilable(Symbol)) }
        def get_pricing_target_type(pricing_target_type)
          case
          when pricing_target_type == "ProductPricing"
            Hydro::Schemas::Billingplatform::V1::Entities::PricingTarget::PricingTargetType.lookup(Hydro::Schemas::Billingplatform::V1::Entities::PricingTarget::PricingTargetType::PRODUCT_PRICING)
          when pricing_target_type == "SkuPricing"
            Hydro::Schemas::Billingplatform::V1::Entities::PricingTarget::PricingTargetType.lookup(Hydro::Schemas::Billingplatform::V1::Entities::PricingTarget::PricingTargetType::SKU_PRICING)
          else
            Hydro::Schemas::Billingplatform::V1::Entities::PricingTarget::PricingTargetType.lookup(Hydro::Schemas::Billingplatform::V1::Entities::PricingTarget::PricingTargetType::SKU_PRICING)
          end
        end

        sig { params(reason_type: T.nilable(Symbol)).returns(T::Boolean) }
        def check_can_proceed_with_usage(reason_type)
          CHECK_CAN_PROCEED_WITH_USAGE_BY_REASON.fetch(reason_type, true)
        end

        def cost_center_resources_to_react_payload(resources)
          reassigned_resources = []

          resources_to_cost_center = { repos: {}, orgs: {}, users: {} }

          resources.each do |r|
            case r[:resource][:type]
            when :Repo
              resources_to_cost_center[:repos][r[:resource][:id].to_i] = r[:previousCostCenterName]
            when :Org
              resources_to_cost_center[:orgs][r[:resource][:id].to_i] = r[:previousCostCenterName]
            when :User
              resources_to_cost_center[:users][r[:resource][:id].to_i] = r[:previousCostCenterName]
            end
          end

          repos = Repository.includes(:internal_repository, :owner)
            .select(:id, :name, :source_id, :public, :owner_id, :owner_login)
            .where(id: resources_to_cost_center[:repos].keys)

          repos.each do |repo|
            reassigned_resources.push(
              {
                name: repo.name_with_display_owner,
                type: "Repo",
                isPublic: repo.public?,
                previousCostCenterName: resources_to_cost_center[:repos][repo.id],
              }
            )
          end

          orgs = Organization.select(:id, :display_login).where(id: resources_to_cost_center[:orgs].keys)
          orgs.each do |org|
            reassigned_resources.push(
              {
                name: org.display_login,
                type: "Org",
                avatarUrl: org.primary_avatar_url(40),
                previousCostCenterName: resources_to_cost_center[:orgs][org.id],
              }
            )
          end

          users = User.select(:id, :display_login, :business_id).where(id: resources_to_cost_center[:users].keys)
          users.each do |user|
            reassigned_resources.push(
              {
                name: user.display_login,
                type: "User",
                avatarUrl: user.primary_avatar_url(40),
                previousCostCenterName: resources_to_cost_center[:users][user.id],
              }
            )
          end

          reassigned_resources
        end
      end
    end
  end
end
