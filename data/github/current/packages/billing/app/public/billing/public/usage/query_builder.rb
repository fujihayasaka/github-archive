# typed: strict
# frozen_string_literal: true

module Billing::Public::Usage::QueryBuilder

  sig do
    params(
      entity: Billing::Types::Account,
      customer_id: T.nilable(T.any(Integer, String)),
      period: T.nilable(T.any(Integer, String)),
      group: T.nilable(String),
      product: T.nilable(String),
      sku: T.nilable(String),
      query: T.nilable(String),
      page: T.nilable(String),
      user_id: T.nilable(String),
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def self.build(entity, customer_id: entity.customer&.id, period: BillingSettingsHelper::USAGE_PERIOD[:this_month], group: nil, product: nil, sku: nil, query: nil, page: nil, user_id: nil)
    current_time = Time.now.utc

    usage_entity_id = get_usage_entity_id(entity, customer_id)

    usage_filters = {
      usage_entity_id: usage_entity_id,
      billing_period: BillingPlatform::Base::BillingPeriod::Monthly,
      year: current_time.year,
      month: current_time.month,
      day: current_time.day,
      hour: current_time.hour
    }

    usage_filters = filter_by_period(usage_filters, period)
    usage_filters = filter_by_query(usage_filters, query, entity, group)
    usage_filters = filter_by_product(usage_filters, product) if !sku&.present?
    usage_filters = filter_by_sku(usage_filters, sku)
    usage_filters = filter_by_group(usage_filters, group)

    usage_filters
  end

  class << self

    private

    sig { params(entity: Billing::Types::Account, customer_id: T.nilable(T.any(Integer, String))).returns(T.nilable(T.any(Integer, String))) }
    def get_usage_entity_id(entity, customer_id)
      # This is a fix to make the usage APIs request usage data only for the current customer
      # and not for an arbitrary customer id passed in the query params.
      # TODO: cost center query params should be extracted to cost_center_id instead.
      customer_id_string = customer_id.to_s.downcase
      cost_center_ids = get_cost_center_ids(entity)
      cost_center_id_regex = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
      if cost_center_id_regex.match?(customer_id_string) && cost_center_ids.include?(customer_id_string)
        customer_id
      else
        entity.customer&.id
      end
    end

    sig { params(entity: Billing::Types::Account).returns(T::Array[String]) }
    def get_cost_center_ids(entity)
      return [] unless entity.is_a?(Business)
      entity.cost_centers&.map { |cc| cc[:costCenterKey][:uuid].downcase } || []
    end

    sig { params(filters: T::Hash[Symbol, T.untyped], period: T.nilable(T.any(Integer, String))).returns(T::Hash[Symbol, T.untyped]) }
    def filter_by_period(filters, period)
      return filters if period.blank?

      current_time = Time.now.utc

      case (period.to_i)
      when BillingSettingsHelper::USAGE_PERIOD[:today]
        filters[:billing_period] = BillingPlatform::Base::BillingPeriod::Daily
      when BillingSettingsHelper::USAGE_PERIOD[:this_month]
        filters[:billing_period] = BillingPlatform::Base::BillingPeriod::Monthly
      when BillingSettingsHelper::USAGE_PERIOD[:last_month]
        filters[:billing_period] = BillingPlatform::Base::BillingPeriod::Monthly
        filters[:year] = current_time.last_month.year
        filters[:month] = current_time.last_month.month
        filters[:day] = current_time.last_month.day
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

      filters[:product] = product.downcase

      filters
    end

    sig { params(filters: T::Hash[Symbol, T.untyped], sku: T.nilable(String)).returns(T::Hash[Symbol, T.untyped]) }
    def filter_by_sku(filters, sku)
      return filters if sku.blank?

      filters[:sku] = sku

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

      # We don't have the ability to use certain query filters on org / repo groupings
      # since data in the byOrgAndRepo partition is product / sku agnostic and searching
      # for a particular org / repo when grouping by org / repo doesn't make sense
      # we are however able to filter by cost center when grouping by org / repo
      is_org_repo_grouping = group.to_i == BillingPlatform::Base::UsageGroupBy::GroupByOrganization || group.to_i == BillingPlatform::Base::UsageGroupBy::GroupByRepository

      # Split the query into parts, but ignore spaces within quotes
      query_parts = query.split(/\s(?=(?:[^"]|"[^"]*")*$)/)
      query_parts.each do |query_part|
        if entity.is_a?(Business) && query_part.start_with?("org:") && !is_org_repo_grouping
          org_slug = query_part.split(":")[1]

          # use the current business to query for organzations to ensure
          # the user is only querying resources they have access to
          orgs = entity.organizations
          org = orgs.find_by(login: org_slug)
          org_id = org&.id

          # set -1 for ID if a org is not found to still attempt to lookup data in the correct partition
          filters[:org_id] = org_id.present? ? org_id : -1
        end
        if query_part.start_with?("repo:") && !is_org_repo_grouping
          # a repo name with owner is the org/user prepended to the repo name (e.g. github/gitcoin)
          repo_name_with_owner = query_part.split(":")[1].to_s
          owner_login = repo_name_with_owner.split("/")[0].to_s
          repo_name = repo_name_with_owner.split("/")[1].to_s

          # use the current business to query for organzations and repos
          # to ensure the user is only querying resources they have access to
          if entity.is_a?(Business)
            orgs = entity.organizations
            org = orgs.find_by(login: owner_login)
            repo = org&.repositories&.find_by(name: repo_name)
            repo_id = repo&.id
          else
            repo = entity.repositories.find_by(name: repo_name)
            repo_id = repo&.id
          end

          # set -1 for ID if a repo is not found to still attempt to lookup data in the correct partition
          filters[:repo_id] = repo_id.present? ? repo_id : -1
        end
        if entity.is_a?(Business) && query_part.start_with?("cost_center:")
          cost_center_name = query_part.split(":")[1]&.delete("\"")
          if cost_center_name&.casecmp?("none")
            filters[:cost_center_id] = "none"
          else
            customer_cost_centers = Billing::Platform::Api::Client.new.get_all_cost_centers(customer_id: entity.customer&.id.to_s, use_cache: true)
            if customer_cost_centers.is_a?(Hash) && customer_cost_centers[:costCenters]
              customer_cost_centers[:costCenters].each do |cc|
                if cc[:name]&.downcase == cost_center_name&.downcase
                  filters[:cost_center_id] = cc[:costCenterKey][:uuid]
                  break
                end
              end
            end
            # cost_center_id is string-based (UUID/none/blank), so use "-1" if no match.
            # Unlike org/repo (-1 sentinel), -1 here causes client errors. "-1" returns empty usage,
            # matching controller tests and showing "No usage found" in UI.
            filters[:cost_center_id] = "-1" unless filters.key?(:cost_center_id)
          end
        end
        if (query_part.start_with? "sku:") && !is_org_repo_grouping
          filters[:sku] = query_part.split(":")[1]&.downcase
        end
        if (query_part.start_with? "product:") && !is_org_repo_grouping
          filters[:product] = query_part.split(":")[1]&.downcase
        end
        if query_part.start_with? "user:"
          user_login = query_part.split(":")[1]
          user = User.find_by(login: user_login)
          filters[:user_id] = user&.id
        end
        if query_part.start_with? "model:"
          filters[:model] = query_part.split(":")[1]&.downcase
        end
      end

      filters
    end
  end
end
