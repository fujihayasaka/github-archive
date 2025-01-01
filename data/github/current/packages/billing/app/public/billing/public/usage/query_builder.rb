# typed: strict
# frozen_string_literal: true

module Billing::Public::Usage::QueryBuilder
  extend T::Sig

  sig do
    params(
      entity: Billing::Types::Account,
      customer_id: T.nilable(T.any(Integer, String)),
      period: T.nilable(T.any(Integer, String)),
      group: T.nilable(String),
      product: T.nilable(String),
      query: T.nilable(String),
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def self.build(entity, customer_id: entity.customer&.id, period: BillingSettingsHelper::USAGE_PERIOD[:this_month], group: nil, product: nil, query: nil)
    current_time = Time.now.utc

    usage_filters = {
      usage_entity_id: customer_id,
      billing_period: BillingPlatform::Base::BillingPeriod::Monthly,
      year: current_time.year,
      month: current_time.month,
      day: current_time.day,
      hour: current_time.hour
    }

    usage_filters = filter_by_period(usage_filters, period)
    usage_filters = filter_by_query(usage_filters, query, entity, group)
    usage_filters = filter_by_product(usage_filters, product)
    usage_filters = filter_by_group(usage_filters, group)

    usage_filters
  end

  class << self
    extend T::Sig

    private

    sig { params(filters: T::Hash[Symbol, T.untyped], period: T.nilable(T.any(Integer, String))).returns(T::Hash[Symbol, T.untyped]) }
    def filter_by_period(filters, period)
      return filters if period.blank?

      current_time = Time.now.utc

      case (period.to_i)
      when BillingSettingsHelper::USAGE_PERIOD[:this_hour]
        filters[:billing_period] = BillingPlatform::Base::BillingPeriod::Hourly
      when BillingSettingsHelper::USAGE_PERIOD[:today]
        filters[:billing_period] = BillingPlatform::Base::BillingPeriod::Daily
      when BillingSettingsHelper::USAGE_PERIOD[:this_month]
        filters[:billing_period] = BillingPlatform::Base::BillingPeriod::Monthly
      when BillingSettingsHelper::USAGE_PERIOD[:last_month]
        filters[:billing_period] = BillingPlatform::Base::BillingPeriod::Monthly
        filters[:year] = current_time.last_month.year
        filters[:month] = current_time.last_month.month
      when BillingSettingsHelper::USAGE_PERIOD[:this_year]
        filters[:billing_period] = BillingPlatform::Base::BillingPeriod::Yearly
      when BillingSettingsHelper::USAGE_PERIOD[:last_year]
        filters[:billing_period] = BillingPlatform::Base::BillingPeriod::Yearly
        filters[:year] = current_time.last_year.year
      else
        filters[:billing_period] = BillingPlatform::Base::BillingPeriod::Unspecified
      end

      filters
    end

    sig { params(filters: T::Hash[Symbol, T.untyped], group: T.nilable(String)).returns(T::Hash[Symbol, T.untyped]) }
    def filter_by_group(filters, group)
      return filters if group.blank?

      filters[:group_by] = group.to_i

      filters
    end

    sig { params(filters: T::Hash[Symbol, T.untyped], product: T.nilable(String)).returns(T::Hash[Symbol, T.untyped]) }
    def filter_by_product(filters, product)
      return filters if product.blank?

      filters[:product] = product

      filters
    end

    sig do
      params(
        filters: T::Hash[Symbol, T.untyped],
        query: T.nilable(String),
        entity: Billing::Types::Account,
        group: T.nilable(String)
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def filter_by_query(filters, query, entity, group)
      return filters if query.blank?

      # We don't have the ability to use query filters on org / repo groupings
      # since data in the byOrgAndRepo partition is product / sku agnostic and searching
      # for a particular org / repo when grouping by org / repo doesn't make sense
      is_org_repo_grouping = group.to_i == BillingPlatform::Base::UsageGroupBy::GroupByOrganization || group.to_i == BillingPlatform::Base::UsageGroupBy::GroupByRepository
      return filters if is_org_repo_grouping

      # Split the query into parts, but ignore spaces within quotes
      query_parts = query.split(/\s(?=(?:[^"]|"[^"]*")*$)/)
      query_parts.each do |query_part|
        if entity.is_a?(Business) && query_part.start_with?("org:")
          org_slug = query_part.split(":")[1]

          # use the current business to query for organzations to ensure
          # the user is only querying resources they have access to
          orgs = entity.organizations
          org = orgs.find_by(login: org_slug)
          org_id = org&.id

          # set -1 for ID if a org is not found to still attempt to lookup data in the correct partition
          filters[:org_id] = org_id.present? ? org_id : -1
        end
        if entity.is_a?(Business) && query_part.start_with?("repo:")
          # a repo name with owner is the org/user prepended to the repo name (e.g. github/gitcoin)
          repo_name_with_owner = query_part.split(":")[1].to_s
          owner_login = repo_name_with_owner.split("/")[0].to_s
          repo_name = repo_name_with_owner.split("/")[1].to_s

          # use the current business to query for organzations and repos
          # to ensure the user is only querying resources they have access to
          orgs = entity.organizations
          org = orgs.find_by(login: owner_login)
          repo = org&.repositories&.find_by(name: repo_name)
          repo_id = repo&.id

          # set -1 for ID if a repo is not found to still attempt to lookup data in the correct partition
          filters[:repo_id] = repo_id.present? ? repo_id : -1
        end
        if entity.is_a?(Business) && query_part.start_with?("cost_center:")
          cost_center_name = query_part.split(":")[1]&.delete("\"")
          if cost_center_name == "None"
            filters[:cost_center_id] = "none"
          else
            customer_cost_centers = Billing::Platform::Api::Client.new.get_all_cost_centers(customer_id: entity.customer&.id.to_s)
            customer_cost_centers[:costCenters].each do |cc|
              if cc[:name] == cost_center_name
                filters[:cost_center_id] = cc[:costCenterKey][:uuid]
                break
              end
            end
          end
        end
        if query_part.start_with? "sku:"
          filters[:sku] = query_part.split(":")[1]
        end
        if query_part.start_with? "product:"
          filters[:product] = query_part.split(":")[1]
        end
      end

      filters
    end
  end
end
