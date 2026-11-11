# typed: strict
# frozen_string_literal: true

module Billing::DiscountsDependency
  extend T::Helpers

  include Billing::Platform::Api::Utils
  include BillingSettingsHelper

  requires_ancestor { ApplicationController }
  abstract!

  FIXED_AMOUNT_DISCOUNT_TYPE_STRING = T.let("FixedAmount".freeze, String)
  RECURRING_FIXED_AMOUNT_DISCOUNT_TYPE_STRING = T.let("RecurringFixedAmount".freeze, String)
  PERCENTAGE_DISCOUNT_TYPE_STRING = T.let("Percentage".freeze, String)
  NO_DISCOUNT_TYPE_STRING = T.let("NoDiscountType".freeze, String)

  BILLING_CORRECTION_FUNDING_SOURCE_STRING = T.let("BillingCorrection".freeze, String)
  GITHUB_FOR_STARTUPS_FUNDING_SOURCE_STRING = T.let("GitHubForStartups".freeze, String)
  SOCIAL_IMPACT_FUNDING_SOURCE_STRING = T.let("SocialImpact".freeze, String)
  OPEN_SOURCE_FUNDING_SOURCE_STRING = T.let("OpenSource".freeze, String)
  EDUCATION_FUNDING_SOURCE_STRING = T.let("Education".freeze, String)
  SALES_OFFER_FUNDING_SOURCE_STRING = T.let("SalesOffer".freeze, String)
  PLAN_FUNDING_SOURCE_STRING = T.let("Plan".freeze, String)
  PUBLIC_REPOSITORY_FUNDING_SOURCE_STRING = T.let("PublicRepository".freeze, String)
  NO_FUNDING_SOURCE_STRING = T.let("NoFundingSource".freeze, String)

  sig { abstract.returns(String) }
  def customer_id; end

  sig { abstract.params(entity: ::Billing::Types::Account).returns(T::Array[T.untyped]) }
  def enabled_products(entity); end

  sig { params(this_entity: ::Billing::Types::Account, is_stafftools_route: T::Boolean).void }
  def render_discounts_index(this_entity:, is_stafftools_route: false)
    discount_data_result = get_discount_states(this_entity, is_stafftools_route)

    respond_to do |format|
      format.json do
        if discount_data_result[:error]
          return render json: { error: discount_data_result[:error], discounts: [] }, status: discount_data_result[:status] || 500
        end
        render json: { discounts: discount_data_result[:discount_states] }, status: 200
      end

      format.html do
        if !is_stafftools_route
          head :no_content
        else
          payload = {
            customer: customer_payload(this_entity),
            enabledProducts: enabled_products(this_entity),
            isCopilotPremiumUsageReportEnabled: copilot_premium_usage_report_enabled?(this_entity),
            discounts: discount_data_result[:error] ? [] : discount_data_result[:discount_states]
          }

          if discount_data_result[:error]
            render_react_app(payload: payload, status: discount_data_result[:status] || 500)
          else
            render_react_app(payload: payload)
          end
        end
      end
    end
  end

  private

  sig { params(this_entity: ::Billing::Types::Account).returns(T::Boolean) }
  def copilot_premium_usage_report_enabled?(this_entity)
    # saving this_entity to a local variable to help Sorbet with type narrowing
    # in the case statement.
    entity = this_entity

    return false unless entity.feature_flag_enabled_or_raise?(:copilot_overages_usage_report) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

    case (entity)
    when Organization
      Copilot::Organization.new(entity).can_export_premium_usage?
    when User
      Copilot::User.new(entity).can_export_premium_usage?
    when Business
      Copilot::Business.new(entity).can_export_premium_usage?
    end
  end
  sig { returns(Billing::Platform::Api::Client) }
  def billing_platform_client
    Billing::Platform::Api::Client.new
  end

  sig { params(this_entity: ::Billing::Types::Account).returns(T::Boolean) }
  def enterprise_org_owner_but_not_enterprise_owner?(this_entity)
    roles = admin_roles(this_entity)
    roles.include?("enterprise_org_owner") && !roles.include?("owner")
  end

  sig { params(discount_type: T.untyped).returns(T.untyped) }
  def discount_type(discount_type)
    case discount_type
    when FIXED_AMOUNT_DISCOUNT_TYPE_STRING
      BillingPlatform::Api::V1::DiscountType::FixedAmount
    when RECURRING_FIXED_AMOUNT_DISCOUNT_TYPE_STRING
      BillingPlatform::Api::V1::DiscountType::RecurringFixedAmount
    when PERCENTAGE_DISCOUNT_TYPE_STRING
      BillingPlatform::Api::V1::DiscountType::Percentage
    else
      BillingPlatform::Api::V1::DiscountType::NoDiscountType
    end
  end

  sig { params(discount_type_constant: T.untyped).returns(T.nilable(String)) }
  def discount_type_to_string(discount_type_constant)
    case discount_type_constant
    when BillingPlatform::Api::V1::DiscountType::FixedAmount
      FIXED_AMOUNT_DISCOUNT_TYPE_STRING
    when BillingPlatform::Api::V1::DiscountType::RecurringFixedAmount
      RECURRING_FIXED_AMOUNT_DISCOUNT_TYPE_STRING
    when BillingPlatform::Api::V1::DiscountType::Percentage
      PERCENTAGE_DISCOUNT_TYPE_STRING
    when BillingPlatform::Api::V1::DiscountType::NoDiscountType
      NO_DISCOUNT_TYPE_STRING
    end
  end

  sig { params(discount_type: T.nilable(Integer)).returns(T::Boolean) }
  def valid_discount_type?(discount_type)
    return false if discount_type.nil?
    [
      BillingPlatform::Api::V1::DiscountType::Percentage,
      BillingPlatform::Api::V1::DiscountType::RecurringFixedAmount,
      BillingPlatform::Api::V1::DiscountType::FixedAmount
    ].include?(discount_type)
  end

  sig { params(funding_source: T.untyped).returns(T.untyped) }
  def funding_source(funding_source)
    case funding_source
    when BILLING_CORRECTION_FUNDING_SOURCE_STRING
      BillingPlatform::Api::V1::FundingSource::BillingCorrection
    when GITHUB_FOR_STARTUPS_FUNDING_SOURCE_STRING
      BillingPlatform::Api::V1::FundingSource::GitHubForStartups
    when SOCIAL_IMPACT_FUNDING_SOURCE_STRING
      BillingPlatform::Api::V1::FundingSource::SocialImpact
    when OPEN_SOURCE_FUNDING_SOURCE_STRING
      BillingPlatform::Api::V1::FundingSource::OpenSource
    when EDUCATION_FUNDING_SOURCE_STRING
      BillingPlatform::Api::V1::FundingSource::Education
    when SALES_OFFER_FUNDING_SOURCE_STRING
      BillingPlatform::Api::V1::FundingSource::SalesOffer
    when PLAN_FUNDING_SOURCE_STRING
      BillingPlatform::Api::V1::FundingSource::Plan
    else
      BillingPlatform::Api::V1::FundingSource::NoFundingSource
    end
  end

  sig { params(funding_source_constant: T.untyped).returns(T.nilable(String)) }
  def funding_source_to_string(funding_source_constant)
    case funding_source_constant
    when BillingPlatform::Api::V1::FundingSource::BillingCorrection
      BILLING_CORRECTION_FUNDING_SOURCE_STRING
    when BillingPlatform::Api::V1::FundingSource::GitHubForStartups
      GITHUB_FOR_STARTUPS_FUNDING_SOURCE_STRING
    when BillingPlatform::Api::V1::FundingSource::SocialImpact
      SOCIAL_IMPACT_FUNDING_SOURCE_STRING
    when BillingPlatform::Api::V1::FundingSource::OpenSource
      OPEN_SOURCE_FUNDING_SOURCE_STRING
    when BillingPlatform::Api::V1::FundingSource::Education
      EDUCATION_FUNDING_SOURCE_STRING
    when BillingPlatform::Api::V1::FundingSource::SalesOffer
      SALES_OFFER_FUNDING_SOURCE_STRING
    when BillingPlatform::Api::V1::FundingSource::Plan
      PLAN_FUNDING_SOURCE_STRING
    when BillingPlatform::Api::V1::FundingSource::PublicRepository
      PUBLIC_REPOSITORY_FUNDING_SOURCE_STRING
    when BillingPlatform::Api::V1::FundingSource::NoFundingSource
      NO_FUNDING_SOURCE_STRING
    end
  end

  # Only allow certain funding sources for discounts created via the UI
  sig { params(funding_source: T.nilable(Integer)).returns(T::Boolean) }
  def valid_funding_source?(funding_source)
    return false if funding_source.nil?
    [
      BillingPlatform::Api::V1::FundingSource::BillingCorrection,
      BillingPlatform::Api::V1::FundingSource::GitHubForStartups,
      BillingPlatform::Api::V1::FundingSource::SocialImpact,
      BillingPlatform::Api::V1::FundingSource::OpenSource,
      BillingPlatform::Api::V1::FundingSource::Education,
      BillingPlatform::Api::V1::FundingSource::SalesOffer
    ].include?(funding_source)
  end


  sig { params(request: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
  def parse_discount_body(request)
    body = JSON.parse(request.body.read).symbolize_keys.slice(*%i(customerId endDate percentage startDate targets targetAmount discountType fundingSource))
  end

  sig { params(body: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
  def discount_params(body)
    body[:customerId] = body[:customerId].to_s if body[:customerId]

    if body[:targets]
      body[:targets] = body[:targets].map do |target|
        incoming_id = target["id"].to_s
        type = target["type"]
        # Repo and Org targets from the UI will arrive as global IDs and should be decoded into database IDs before sending to billing-platform
        case type
        when "OrgDiscount", "RepoDiscount"
          { id: Platform::Helpers::NodeIdentification.from_global_id(incoming_id).last.to_s, type: type }
        else
          { id: incoming_id, type: type }
        end
      end
    end

    body[:discountType] = discount_type(body[:discountType])
    body[:fundingSource] = funding_source(body[:fundingSource])

    body
  end

  sig { params(entity: ::Billing::Types::Account, customer_id: String).void }
  def handle_discount_create(entity:, customer_id:)
    discount_request_body = parse_discount_body(request)
    discount_params = discount_params(discount_request_body)

    unless valid_discount_type?(discount_params[:discountType])
      return render json: { error: "Invalid discount type" }, status: :bad_request
    end

    if !valid_funding_source?(discount_params[:fundingSource])
      return render json: { error: "Invalid funding source" }, status: :bad_request
    end

    response = billing_platform_client.create_discount(discount: discount_params)
    if response.is_a?(Billing::Platform::Api::Error)
      return render json: { error: "Unable to create credit" }, status: 500
    end

    audit_log_payload = {
      actor: current_user,
      business: entity,
      customer_id: customer_id,
      targets: discount_params[:targets],
      discount_amount: discount_params[:targetAmount],
      percentage: discount_params[:percentage],
      discount_type: discount_type_to_string(discount_params[:discountType]),
      start_date: Time.at(discount_params[:startDate]).strftime("%Y-%m-%d %H:%M:%S"),
      end_date: Time.at(discount_params[:endDate]).strftime("%Y-%m-%d %H:%M:%S"),
      funding_source: funding_source_to_string(discount_params[:fundingSource])
    }
    GitHub.instrument("billing.credits_create", audit_log_payload)

    render_react_app payload: {}
  end

  sig { params(entity: ::Billing::Types::Account, customer_id: String).void }
  def handle_discount_delete(entity:, customer_id:)
    discount_uuid = params[:id]

    unless discount_uuid.present?
      return render json: { error: "Discount UUID is required" }, status: :bad_request
    end

    response = billing_platform_client.delete_discount(customer_id: customer_id, discount_uuid: discount_uuid)
    if response.is_a?(Billing::Platform::Api::Error)
      return render json: { error: "Unable to delete credit" }, status: 500
    end

    audit_log_payload = {
      actor: current_user,
      business: entity,
      customer_id: customer_id,
      discount_uuid: discount_uuid
    }
    GitHub.instrument("billing.credits_delete", audit_log_payload)

    render json: { success: true }, status: 200
  end

  sig { params(this_entity: ::Billing::Types::Account, is_stafftools_route: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
  def get_discount_states(this_entity, is_stafftools_route)
    discount_states = []

    year = params.has_key?(:year) ? params[:year].to_i : Time.now.utc.year
    month = params.has_key?(:month) ? params[:month].to_i : Time.now.utc.month
    filter_included_usage = params.has_key?(:filter_included_usage) && params[:filter_included_usage] == "true"

    user_owned_org_ids = current_user.owned_organization_ids

    if user_owned_org_ids.any? && enterprise_org_owner_but_not_enterprise_owner?(this_entity)

      net_items_response = billing_platform_client.get_net_usage_line_items(
        usage_entity_id: customer_id,
        billing_period: BillingSettingsHelper::USAGE_PERIOD[:this_month],
        year: year,
        month: month,
        organization_ids: user_owned_org_ids,
      )

      if net_items_response.is_a?(Billing::Platform::Api::Error)
        return { error: "Unable to retrieve organizations' net usage line items", status: 500 }
      end

      net_usage_items = net_items_response[:netUsageItems]

      return { discount_states: discount_states } if net_usage_items.empty?

      # Tally all the org level discounts
      enabled_product_names = enabled_products(this_entity).map { |product| product[:name] }
      total_orgs_discounts = net_usage_items.sum do |item|
        enabled_product_names.include?(item[:product]) ? item[:discountAmount] : 0
      end

      # Instead of sending an array of net usage line items to the UI, we calculate the total orgs discount on the backend
      # and send a single discount state placeholder response for an enterprise org owner.
      if is_stafftools_route
        discount_states = [
          {
            "isFullyApplied": false,
            "currentAmount": total_orgs_discounts,
            "targetAmount": 0.0,
            "percentage": 0.0,
            "uuid": "",
            "name": this_entity.name,
            "targets": [
              {
                  "id": "",
                  "type": "NoDiscountTarget"
              }
            ]
          },
        ]
      else
        discount_states = [
          {
            "isFullyApplied": false,
            "currentAmount": total_orgs_discounts,
            "targetAmount": 0.0,
            "percentage": 0.0,
            "uuid": "",
            "targets": [
              {
                  "id": "",
                  "type": "NoDiscountTarget"
              }
            ]
          },
        ]
      end
    else
      discount_states_responses = if filter_included_usage
        billing_platform_client.get_all_included_usage_discount_states(customer_id: customer_id, year: year, month: month)
      else
        billing_platform_client.get_all_discount_states(customer_id: customer_id, year: year, month: month)
      end

      if discount_states_responses.is_a?(Billing::Platform::Api::Error)
        return { error: "Unable to retrieve discounts", status: 500 }
      end

      # Extract all targets
      targets = discount_states_responses[:discounts].map { |d| d[:targets]&.first }.compact

      # Separate IDs by type
      enterprise_customer_ids, raw_org_ids, raw_repo_ids = [], [], []
      targets.each do |target|
        case target[:type]&.to_sym
        when :EnterpriseDiscount
          enterprise_customer_ids << target[:id]
        when :OrgDiscount
          raw_org_ids << target[:id]
        when :RepoDiscount
          raw_repo_ids << target[:id]
        end
      end

      # Until a transition is run to convert all org and repo targets to database IDs in billing-platform, we need to be tolerant of both global IDs and database IDs.
      org_ids = raw_org_ids.map do |gid|
        # If gid is a numeric string, use it as is since it is already a database ID
        if gid =~ /\A\d+\z/
          gid.to_i
        else
          Platform::Helpers::NodeIdentification.from_global_id(gid.to_s).last
        end
      end

      repo_ids = raw_repo_ids.map do |gid|
        if gid =~ /\A\d+\z/
          gid.to_i
        else
          Platform::Helpers::NodeIdentification.from_global_id(gid.to_s).last
        end
      end

      # Query once per model and build lookup maps
      business_names = Business.where(customer_id: enterprise_customer_ids).pluck(:customer_id, :name).to_h
      org_names = Organization.where(id: org_ids).pluck(:id, :display_login).to_h
      repo_names = Repository.where(id: repo_ids).index_by(&:id).transform_values(&:full_name)

      # Build reverse lookup for decoded global IDs
      org_raw_id_to_name = raw_org_ids.zip(org_ids).to_h.transform_values { |id| org_names[id] }
      repo_raw_id_to_name = raw_repo_ids.zip(repo_ids).to_h.transform_values { |id| repo_names[id] }

      # Resolve names in the loop
      discount_states = discount_states_responses[:discounts].map do |discount|
        # avoid mutating the original response
        discount = discount.dup

        # Sanitize nested discount object: remove customerId.
        if discount[:discount].is_a?(Hash)
          discount[:discount] = discount[:discount].except(:customerId, "customerId")
        end

        target = discount[:targets]&.first || {}
        target_id = target[:id]
        target_type = target[:type]&.to_sym

        name = case target_type
        when :EnterpriseDiscount
          business_names[target_id.to_i]
        when :OrgDiscount
          org_raw_id_to_name[target_id]
        when :RepoDiscount
          repo_raw_id_to_name[target_id]
        when :ProductDiscount
          target_id
        when :SkuDiscount
          target_id
        else
          nil
        end

        discount.merge(name: name)
      end
    end

    { discount_states: discount_states }
  end
end
