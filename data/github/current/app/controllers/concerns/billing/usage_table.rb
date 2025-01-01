# typed: strict
# frozen_string_literal: true

module Billing::UsageTable
  include Billing::Platform::Api::Utils
  include AvatarHelper
  extend ActiveSupport::Concern

  extend T::Helpers

  requires_ancestor { ApplicationController }

  abstract!

  USAGE_TABLE_ROWS_PER_PAGE = 10

  sig { params(this_entity: ::Billing::Types::Account, is_stafftools_route: T::Boolean).void }
  def render_usage_table_data(this_entity:, is_stafftools_route: false)
    respond_to do |format|
      format.json do
        query = Billing::Public::Usage::QueryBuilder.build(this_entity, **usage_filter_params)
        query[:organization_ids] = (should_filter_for_org_admin?(this_entity, current_user) && !is_stafftools_route) ? get_org_ids_for_org_admin(this_entity, current_user) : nil

        is_group_by_org_or_repo = org_or_repo_request?(query)
        is_filter_by_org_or_repo = query[:org_id].present? || query[:repo_id].present?

        if query[:cost_center_id].nil? || query[:cost_center_id] == ""
          query[:cost_center_id] = ""
        end

        if is_group_by_org_or_repo && !is_filter_by_org_or_repo
          usage_response = billing_platform_client.get_top_org_repo_usage_line_items(
            usage_entity_id: query[:usage_entity_id],
            billing_period: query[:billing_period],
            year: query[:year],
            month: query[:month],
            day: query[:day],
            hour: query[:hour],
            group_by: query[:group_by],
            cost_center_id: query[:cost_center_id],
            organization_ids: query[:organization_ids],
            include_discounts: true
          )
          if usage_response.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "An unknown error occurred", usage: [] }, status: 500
          end

          usage = usage_response
        else
          usage_response = billing_platform_client.get_net_usage_line_items(
            usage_entity_id: query[:usage_entity_id],
            product: query[:product],
            sku: query[:sku],
            billing_period: query[:billing_period],
            year: query[:year],
            month: query[:month],
            day: query[:day],
            hour: query[:hour],
            org_id: query[:org_id],
            repo_id: query[:repo_id],
            group_by: query[:group_by],
            cost_center_id: query[:cost_center_id],
            organization_ids: query[:organization_ids]
          )
          if usage_response.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "An unknown error occurred", usage: [] }, status: 500
          end

          usage = usage_response[:netUsageItems]
        end

        if is_group_by_org_or_repo
          response = {}

          if is_filter_by_org_or_repo
            response[:usage] = json_billing_items(usage)
          else
            response[:usage] = json_org_repo_billing_items(usage[:topUsages], query[:group_by])
            response[:other] = json_other_billing_items(usage[:otherUsages])
          end

          render json: response, status: 200
        else
          render json: { usage: json_billing_items(usage) }, status: 200
        end
      end
    end
  end

  sig { params(this_entity: ::Billing::Types::Account, is_stafftools_route: T::Boolean, page: T.nilable(Integer)).void }
  def render_copilot_usage_table_data(this_entity:, is_stafftools_route: false, page: nil)
    respond_to do |format|
      format.json do
        query = Billing::Public::Usage::QueryBuilder.build(this_entity, **usage_filter_params)
        page_int = page.to_i
        new_query = {
          customer_id: query[:usage_entity_id],
          year: query[:year],
          month: query[:month],
          billing_period: query[:billing_period],
          org_id: query[:org_id],
          user_id: query[:user_id],
          model: query[:model],
          group_by: query[:group_by],
          cost_center_id: query[:cost_center_id],
          organization_admin_ids: filtered_orgs(is_stafftools_route: is_stafftools_route, this_entity: this_entity),
          page: page_int,
          rows_per_page: USAGE_TABLE_ROWS_PER_PAGE,
        }

        begin
          usage_response = billing_platform_client.get_copilot_usage_table(**new_query)
        rescue => e # rubocop:todo Lint/RescueException
          Failbot.report(e, app: "billing-platform")
          return render json: { error: "Unable to query usage", usage: [] }, status: 500
        end

        if usage_response.is_a?(Billing::Platform::Api::Error)
          return render json: { error: "An unknown error occurred", usage: [] }, status: 500
        end

        # augment the usage response with org or user data here
        if group_by_org?(query) || group_by_user?(query)
          user_org_ids = usage_response[:table][:rows].map do |row|
            if valid_int?(row[:cells][0][:value])
              row[:cells][0][:value].to_i
            else
              next
            end
          end.uniq.compact

          user_org_map = if group_by_org?(query)
            Organization.where(id: user_org_ids).map do |org|
              [org.id, { slug: org.display_login, avatarSrc: avatar_url_for(org, 16), name: org.safe_profile_name }]
            end.to_h
          else # this means group_by_user
            User.where(id: user_org_ids).map do |user|
              [user.id, { slug: user.display_login, avatarSrc: avatar_url_for(user, 16), name: user.display_login }]
            end.to_h
          end

          usage_response[:table][:rows].each do |row|
            user_org_data = user_org_map[row[:id].to_i]
            if user_org_data
              row[:cells][0][:slug] = user_org_data[:slug]
              row[:cells][0][:avatarSrc] = user_org_data[:avatarSrc]
              row[:cells][0][:name] = user_org_data[:name]
            else
              row[:cells][0][:slug] = ""
              row[:cells][0][:avatarSrc] = ""
              row[:cells][0][:name] = ""
            end
          end
        end

        if include_quota?(query: query, entity: this_entity)
          # Preload all user objects to avoid N+1 queries
          if group_by_user?(query)
            user_ids = usage_response[:table][:rows].map { |row| row[:id].to_i }.compact.uniq
            users_by_id = User.where(id: user_ids).index_by(&:id)
          else
            single_user = query[:user_id].present? ? User.find_by(id: query[:user_id].to_i) : nil
          end

          usage_response[:table][:rows].each do |row|
            user = if group_by_user?(query)
              user_id = row[:id].to_i
              users_by_id[user_id]
            else
              single_user
            end

            next unless user
            quota = user_premium_requests_quota(user: user)
            row[:premiumRequestsQuota] = quota.to_s
          end
        end

        render json: usage_response, status: 200
      end
    end
  end

  protected

  sig { params(is_stafftools_route: T::Boolean, this_entity: ::Billing::Types::Account).returns(T.nilable(T::Array[String])) }
  def filtered_orgs(is_stafftools_route:, this_entity:)
    if is_stafftools_route
      # Don't filter out any data for stafftools routes
      return nil
    end
    # Only business requests will need to filter data by a specific org
    if should_filter_usage_for_business?(this_entity, current_user)
      if this_entity.is_a?(Business)
        get_org_ids_for_org_admin(this_entity, current_user)
      else
        nil
      end
    end
  end

  sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
  def usage_filter_params; end

  sig { abstract.returns(Billing::Platform::Api::Client) }
  def billing_platform_client; end

  sig { params(query: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
  def group_by_org?(query)
    query[:group_by] == BillingPlatform::Base::UsageGroupBy::GroupByOrganization
  end

  sig { params(query: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
  def group_by_user?(query)
    query[:group_by] == BillingPlatform::Base::UsageGroupBy::GroupByUser
  end

  sig { params(str: T.untyped).returns(T::Boolean) }
  def valid_int?(str)
    str.to_s.match?(/\A[+-]?\d+\z/)
  end

  sig { params(user: User).returns(Integer) }
  def user_premium_requests_quota(user:)
    copilot_user = Copilot::Public::User.new(user)
    copilot_user.quota_snapshots.dig("premium_interactions", :entitlement) || 0
  end

  sig { params(query: T::Hash[Symbol, T.untyped], entity: ::Billing::Types::Account).returns(T::Boolean) }
  def include_quota?(query:, entity:)
    return false unless FeatureFlag.vexi.enabled?(:show_billing_pru_progress_bars, entity, default: false)
    group_by_user = group_by_user?(query)
    user_query = (query[:user_id].present? && (query[:group_by].blank? || query[:group_by] == BillingPlatform::Base::UsageGroupBy::NoGroupBy))
    monthly_query = query[:billing_period] == BillingSettingsHelper::USAGE_PERIOD[:this_month] || query[:billing_period] == BillingSettingsHelper::USAGE_PERIOD[:last_month]
    (group_by_user || user_query) && monthly_query
  end
end
