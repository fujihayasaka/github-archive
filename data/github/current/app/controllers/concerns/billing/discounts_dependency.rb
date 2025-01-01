# typed: strict
# frozen_string_literal: true

module Billing::DiscountsDependency
  extend T::Helpers

  include Billing::Platform::Api::Utils
  include BillingSettingsHelper

  requires_ancestor { ApplicationController }
  abstract!

  sig { abstract.returns(String) }
  def customer_id; end

  sig { abstract.params(entity: ::Billing::Types::Account).returns(T::Array[T.untyped]) }
  def enabled_products(entity); end

  sig { params(this_entity: ::Billing::Types::Account, is_stafftools_route: T::Boolean).void }
  def render_discounts_index(this_entity:, is_stafftools_route: false)
    respond_to do |format|
      format.json do
        discounts = []

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
            return render json: { error: "Unable to retrieve organizations' net usage line items", discounts: discounts }, status: 500
          end

          net_usage_items = net_items_response[:netUsageItems]

          return render json: { discounts: discounts }, status: 200 if net_usage_items.empty?

          # Tally all the org level discounts
          enabled_product_names = enabled_products(this_entity).map { |product| product[:name] }
          total_orgs_discounts = net_usage_items.sum do |item|
            enabled_product_names.include?(item[:product]) ? item[:discountAmount] : 0
          end

          # Instead of sending an array of net usage line items to the UI, we calculate the total orgs discount on the backend
          # and send a single discount state placeholder response for an enterprise org owner.
          if is_stafftools_route
            discounts = [
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
            discounts = [
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
            return render json: { error: "Unable to retrieve discounts", discounts: discounts }, status: 500
          end

          if is_stafftools_route
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
            discounts = discount_states_responses[:discounts].map do |discount|
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
              else
                nil
              end

              discount.merge(name: name)
            end
          else
            discounts = discount_states_responses[:discounts]
          end
        end
        return render json: { discounts: discounts }, status: 200
      end
      format.html do
        if !is_stafftools_route
          head :no_content
        else
          render_react_app(
            payload: {
              customer: customer_payload(this_entity),
              enabledProducts: enabled_products(this_entity),
              isCopilotPremiumUsageReportEnabled: copilot_premium_usage_report_enabled?(this_entity)
            },
          )
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
    when "fixed-amount"
      BillingPlatform::Api::V1::DiscountType::FixedAmount
    when "recurring-fixed-amount"
      BillingPlatform::Api::V1::DiscountType::RecurringFixedAmount
    when "percentage"
      BillingPlatform::Api::V1::DiscountType::Percentage
    else
      BillingPlatform::Api::V1::DiscountType::NoDiscountType
    end
  end

  sig { params(discount_type_constant: T.untyped).returns(T.nilable(String)) }
  def discount_type_to_string(discount_type_constant)
    case discount_type_constant
    when BillingPlatform::Api::V1::DiscountType::FixedAmount
      "fixed-amount"
    when BillingPlatform::Api::V1::DiscountType::RecurringFixedAmount
      "recurring-fixed-amount"
    when BillingPlatform::Api::V1::DiscountType::Percentage
      "percentage"
    when BillingPlatform::Api::V1::DiscountType::NoDiscountType
      "no-discount"
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
    when "billing-correction"
      BillingPlatform::Api::V1::FundingSource::BillingCorrection
    when "github-for-startups"
      BillingPlatform::Api::V1::FundingSource::GitHubForStartups
    when "social-impact"
      BillingPlatform::Api::V1::FundingSource::SocialImpact
    when "open-source"
      BillingPlatform::Api::V1::FundingSource::OpenSource
    when "education"
      BillingPlatform::Api::V1::FundingSource::Education
    else
      BillingPlatform::Api::V1::FundingSource::NoFundingSource
    end
  end

  sig { params(funding_source_constant: T.untyped).returns(T.nilable(String)) }
  def funding_source_to_string(funding_source_constant)
    case funding_source_constant
    when BillingPlatform::Api::V1::FundingSource::BillingCorrection
      "billing-correction"
    when BillingPlatform::Api::V1::FundingSource::GitHubForStartups
      "github-for-startups"
    when BillingPlatform::Api::V1::FundingSource::SocialImpact
      "social-impact"
    when BillingPlatform::Api::V1::FundingSource::OpenSource
      "open-source"
    when BillingPlatform::Api::V1::FundingSource::Education
      "education"
    when BillingPlatform::Api::V1::FundingSource::NoFundingSource
      "no-funding-source"
    end
  end

  sig { params(funding_source: T.nilable(Integer)).returns(T::Boolean) }
  def valid_funding_source?(funding_source)
    return false if funding_source.nil?
    [
      BillingPlatform::Api::V1::FundingSource::BillingCorrection,
      BillingPlatform::Api::V1::FundingSource::GitHubForStartups,
      BillingPlatform::Api::V1::FundingSource::SocialImpact,
      BillingPlatform::Api::V1::FundingSource::OpenSource,
      BillingPlatform::Api::V1::FundingSource::Education
    ].include?(funding_source)
  end


  sig { params(request: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
  def parse_discount_body(request)
    body = JSON.parse(request.body.read).symbolize_keys.slice(*%i(customerId endDate percentage startDate targets targetAmount discountType fundingSource))
  end

  sig { params(body: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
  def discount_params(body)
    body[:customerId] = body[:customerId].to_s if body[:customerId]

    if FeatureFlag.vexi.enabled?("billing_decode_discount_targets", current_user, default: false)
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
    else
      body[:targets] = body[:targets].map { |target| { id: target["id"].to_s, type: target["type"] } } if body[:targets]
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
end
