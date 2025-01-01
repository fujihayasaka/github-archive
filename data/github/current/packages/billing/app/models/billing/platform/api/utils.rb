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

        def get_target_entity_from_id(target_type:, target_id:)
          case target_type
          when CUSTOMER_TARGET, ENTERPRISE_TARGET # remove enterprise when we remove enterprise budgets
            Customer.find_by(id: target_id)
          when REPOSITORY_TARGET
            Repository.find_by(id: target_id)
          when ORGANIZATION_TARGET
            Organization.find_by(id: target_id)
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
            this_entity.owner?(current_user) || this_entity.billing_manager?(current_user)
          when ORGANIZATION_TARGET
            return false unless this_entity.owner?(current_user) || this_entity.billing_manager?(current_user)
            this_entity.organizations.where(id: target_ids).count == target_ids.size
          when REPOSITORY_TARGET
            owned_business_org_ids = current_user.owned_organization_ids & (this_entity.is_a?(Organization) ? [this_entity.id] : this_entity.organization_ids)
            Repository.where(organization_id: owned_business_org_ids, id: target_ids).count == target_ids.size
          when COSTCENTER_TARGET
            true
          end
        end

        def filter_budget_by_role(budgets:, current_user:, entity:)
          non_repo_budgets = budgets.filter { |budget| budget[:budget][:key][:targetType].to_s != REPOSITORY_TARGET }
          if entity.is_a?(Business) && entity.user_is_owner_of_owned_org?(current_user)
            repo_ids = budgets.filter { |budget| budget[:budget][:key][:targetType].to_s == REPOSITORY_TARGET }.map { |budget| budget[:budget][:key][:targetId] }.uniq.compact
            target_repo_ids = current_user.associated_repository_ids(repository_ids: repo_ids)
            repo_budgets = budgets.filter do |budget|
              target_repo_ids.include?(budget[:budget][:key][:targetId].to_i) && budget[:budget][:key][:targetType].to_s == REPOSITORY_TARGET
            end
            if entity.owner?(current_user) || entity.billing_manager?(current_user)
              budgets = (non_repo_budgets + repo_budgets).uniq
            else
              budgets = repo_budgets
            end
          elsif entity.is_a?(Organization) && current_user.owned_organization_ids.include?(entity.id)
            budgets = budgets
          else
            budgets = non_repo_budgets
          end
          budgets
        end

        def filter_repo_usage_by_ownership(usages:, current_user:, business:)
          if business.is_a?(Business) && (business.billing_manager?(current_user) || business.owner?(current_user))
            usages
          elsif business.is_a?(Organization) && business.adminable_by?(current_user)
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

        def json_billing_items(billing_items, org_or_repo_request: false)
          return [] if billing_items.nil?

          billing_items.map { |item| Billing::Platform::Api::NetUsageLineItem.new(item, org_or_repo_request: org_or_repo_request).to_json }
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
      end
    end
  end
end
