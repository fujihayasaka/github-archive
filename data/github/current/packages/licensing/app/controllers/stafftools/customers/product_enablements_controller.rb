# typed: strict
# frozen_string_literal: true

module Stafftools
  module Customers
    class ProductEnablementsController < StafftoolsController
      include ApplicationController::VerifiedFetchDependency
      include ::Licensing::Licensify

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Ballast,
        ApplicationRecord::Repositories,
        only: [:index]

      ProductEnablement = ::Licensify::Services::V1::ProductEnablement
      ProductEnablementType = ::Licensify::Services::V1::ProductEnablementType
      ProductEnablementSourceType = ::Licensify::Services::V1::ProductEnablementSourceType
      Product = ::Licensify::Services::V1::Product

      PRODUCT_MAPPING = T.let({
        "ghas" => Product::PRODUCT_GHAS,
        "code_security" => Product::PRODUCT_CODE_SECURITY,
        "secret_protection" => Product::PRODUCT_SECRET_PROTECTION,
        "sdlc" => Product::PRODUCT_SDLC,
        "copilot" => Product::PRODUCT_COPILOT,
      }.freeze, T::Hash[String, Integer])

      ENABLEMENT_TYPE_MAPPING = T.let({
        "PRODUCT_ENABLEMENT_TYPE_REPO" => ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_REPO,
        "PRODUCT_ENABLEMENT_TYPE_ENTERPRISE_SERVER" => ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_ENTERPRISE_SERVER,
        "PRODUCT_ENABLEMENT_TYPE_VISUAL_STUDIO_SUBSCRIPTION" => ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_VISUAL_STUDIO_SUBSCRIPTION,
        "PRODUCT_ENABLEMENT_TYPE_BUSINESS_TEAM" => ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_BUSINESS_TEAM,
        "PRODUCT_ENABLEMENT_TYPE_USER" => ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_USER,
        "PRODUCT_ENABLEMENT_TYPE_ORG" => ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_ORG,
        "PRODUCT_ENABLEMENT_TYPE_ORG_TEAM" => ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_ORG_TEAM,
      }.freeze, T::Hash[String, Integer])
      SUPPORTED_ENABLEMENT_TYPES = T.let(ENABLEMENT_TYPE_MAPPING.keys.freeze, T::Array[String])

      SOURCE_TYPE_MAPPING = T.let({
        "organization" => ProductEnablementSourceType::PRODUCT_ENABLEMENT_SOURCE_TYPE_ORGANIZATION,
        "enterprise_account" => ProductEnablementSourceType::PRODUCT_ENABLEMENT_SOURCE_TYPE_ENTERPRISE_ACCOUNT,
      }.freeze, T::Hash[String, Integer])

      before_action :dotcom_required
      before_action :customer_required

      sig { void }
      def index
        return render_empty_response unless valid_filters?

        product_enablements_response = fetch_product_enablements
        return render_twirp_error(product_enablements_response) if product_enablements_response.is_a?(Twirp::Error)

        render json: {
          productEnablements: serialize_product_enablements(product_enablements_response.productEnablements.to_a),
          total: product_enablements_response.total,
        }, status: :ok
      end

      private

      sig { returns(Integer) }
      memoize def customer_id
        params.require(:customer_id).to_i
      end

      sig { returns(T.nilable(Customer)) }
      memoize def customer
        Customer.find_by(id: customer_id)
      end

      sig { void }
      def customer_required
        unless customer_id.positive?
          render json: { error: "No customer found" }, status: :not_found
        end
      end

      sig { returns(T.any(::Licensify::Services::V1::GetProductEnablementsResponse, Twirp::Error)) }
      def fetch_product_enablements
        response = licensify_client.get_product_enablements(
          ::Licensify::Services::V1::GetProductEnablementsRequest.new(**product_enablements_request_params)
        )

        error = response.error
        return error if error.present?

        response.data
      rescue Faraday::Error => e
        log_licensify_error(__method__.to_s, e)
        Twirp::Error.internal("Failed to fetch product enablements", message: e.message)
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def product_enablements_request_params
        {
          customerId: customer_id,
          limit: limit,
          offset: offset,
          product: requested_product,
          enablementType: requested_enablement_type,
          enablementId: requested_enablement_id,
          sourceType: requested_source_type,
          sourceId: requested_source_id,
        }.compact
      end

      sig { params(enablements: T::Array[ProductEnablement]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def serialize_product_enablements(enablements)
        targets_by_key = preload_targets(enablements)
        sources_by_key = preload_sources(enablements)

        enablements.map do |enablement|
          target_type = normalized_enablement_type(enablement.enablementType)
          target_id = enablement.enablementId.to_s
          target_record = targets_by_key[[target_type, target_id]]
          source_type, source_id = source_reference_for(enablement, target_record)
          source_record = sources_by_key[[source_type, source_id]]
          enabled_at = timestamp_to_iso8601(enablement.enabledAt)

          {
            product: normalized_product(enablement.product),
            enablement_type: enablement.enablementType.to_s,
            enablement_id: target_id,
            source_type: source_type,
            source_id: source_id,
            plan_name: nil,
            trial_plan: nil,
            created_at: enabled_at,
            updated_at: enabled_at,
            target: entity_payload(target_type, target_id, target_record),
            source: source_type.present? ? entity_payload(source_type, source_id, source_record) : nil,
            details: details_payload(enablement, source_type, source_id),
          }
        end
      end

      sig { params(enablements: T::Array[ProductEnablement]).returns(T::Hash[[String, String], T.untyped]) }
      def preload_targets(enablements)
        repo_ids = enablements.filter do |enablement|
          [:PRODUCT_ENABLEMENT_TYPE_REPO, ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_REPO].include?(enablement.enablementType)
        end.map { |enablement| enablement.enablementId.to_i }
        user_ids = enablements.filter do |enablement|
          [:PRODUCT_ENABLEMENT_TYPE_USER, ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_USER].include?(enablement.enablementType)
        end.map { |enablement| enablement.enablementId.to_i }
        org_ids = enablements.filter do |enablement|
          [:PRODUCT_ENABLEMENT_TYPE_ORG, ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_ORG].include?(enablement.enablementType)
        end.map { |enablement| enablement.enablementId.to_i }
        team_ids = enablements.filter do |enablement|
          [
            :PRODUCT_ENABLEMENT_TYPE_ORG_TEAM,
            :PRODUCT_ENABLEMENT_TYPE_BUSINESS_TEAM,
            ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_ORG_TEAM,
            ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_BUSINESS_TEAM,
          ].include?(enablement.enablementType)
        end.map { |enablement| enablement.enablementId.to_i }

        ActiveRecord::Base.connected_to(role: :reading) do
          {}.tap do |targets|
            ::Repository.where(id: repo_ids.uniq).includes(:owner).each do |repo|
              targets[["repo", repo.id.to_s]] = repo
            end
            ::User.where(id: user_ids.uniq).each do |user|
              targets[["user", user.id.to_s]] = user
            end
            ::Organization.where(id: org_ids.uniq).each do |org|
              targets[["organization", org.id.to_s]] = org
            end
            ::Team.where(id: team_ids.uniq).each do |team|
              key = team.is_a?(::BusinessTeam) ? "business_team" : "org_team"
              targets[[key, team.id.to_s]] = team
            end
          end
        end
      end

      sig { params(enablements: T::Array[ProductEnablement]).returns(T::Hash[[T.nilable(String), T.nilable(String)], T.untyped]) }
      def preload_sources(enablements)
        organization_ids = T.let([], T::Array[Integer])
        business_ids = T.let([], T::Array[Integer])

        enablements.each do |enablement|
          case enablement.sourceType
          when :PRODUCT_ENABLEMENT_SOURCE_TYPE_ORGANIZATION, ProductEnablementSourceType::PRODUCT_ENABLEMENT_SOURCE_TYPE_ORGANIZATION
            organization_ids << enablement.sourceId.to_i
          when :PRODUCT_ENABLEMENT_SOURCE_TYPE_ENTERPRISE_ACCOUNT, ProductEnablementSourceType::PRODUCT_ENABLEMENT_SOURCE_TYPE_ENTERPRISE_ACCOUNT
            business_ids << enablement.sourceId.to_i
          end
        end

        ActiveRecord::Base.connected_to(role: :reading) do
          {}.tap do |sources|
            ::Organization.where(id: organization_ids.uniq).each do |org|
              sources[["organization", org.id.to_s]] = org
            end
            ::Business.where(id: business_ids.uniq).each do |business|
              sources[["enterprise_account", business.id.to_s]] = business
            end
          end
        end
      end

      sig { params(enablement: ProductEnablement, target_record: T.untyped).returns([T.nilable(String), T.nilable(String)]) }
      def source_reference_for(enablement, target_record)
        case enablement.sourceType
        when :PRODUCT_ENABLEMENT_SOURCE_TYPE_ORGANIZATION, ProductEnablementSourceType::PRODUCT_ENABLEMENT_SOURCE_TYPE_ORGANIZATION
          ["organization", enablement.sourceId.to_s]
        when :PRODUCT_ENABLEMENT_SOURCE_TYPE_ENTERPRISE_ACCOUNT, ProductEnablementSourceType::PRODUCT_ENABLEMENT_SOURCE_TYPE_ENTERPRISE_ACCOUNT
          ["enterprise_account", enablement.sourceId.to_s]
        else
          if enablement.enablementType == ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_REPO && target_record.is_a?(::Repository)
            owner = target_record.owner
            if owner.is_a?(::Organization)
              ["organization", owner.id.to_s]
            else
              business = customer&.business
              business ? ["enterprise_account", business.id.to_s] : [nil, nil]
            end
          else
            [nil, nil]
          end
        end
      end

      sig { params(type: T.nilable(String), id: T.nilable(String), record: T.untyped).returns(T::Hash[Symbol, T.nilable(String)]) }
      def entity_payload(type, id, record)
        case record
        when ::Repository
          {
            type: "repository",
            id: record.id.to_s,
            display_name: record.name_with_display_owner,
            avatar_url: record.owner&.primary_avatar_url,
          }
        when ::Organization
          {
            type: "organization",
            id: record.id.to_s,
            display_name: record.display_login,
            avatar_url: record.primary_avatar_url,
          }
        when ::User
          {
            type: "user",
            id: record.id.to_s,
            display_name: record.login,
            avatar_url: record.primary_avatar_url,
          }
        when ::Team
          {
            type: type,
            id: record.id.to_s,
            display_name: record.name,
            avatar_url: nil,
          }
        when ::Business
          {
            type: "enterprise_account",
            id: record.id.to_s,
            display_name: record.name,
            avatar_url: nil,
          }
        else
          {
            type: type,
            id: id,
            display_name: id,
            avatar_url: nil,
          }
        end
      end

      sig { params(enablement: ProductEnablement, source_type: T.nilable(String), source_id: T.nilable(String)).returns(T::Hash[Symbol, T.untyped]) }
      def details_payload(enablement, source_type, source_id)
        {
          product: enablement.product.to_s,
          enablement_type: enablement.enablementType.to_s,
          enablement_id: enablement.enablementId.to_s,
          global_id: enablement.globalId,
          source_type: source_type,
          source_id: source_id,
          enabled_at: timestamp_to_iso8601(enablement.enabledAt),
          plan_name: nil,
          trial_plan: nil,
        }
      end

      sig { void }
      def render_empty_response
        render json: { productEnablements: [], total: 0 }, status: :ok
      end

      sig { returns(Integer) }
      def limit
        parsed_limit = params[:limit].to_i
        return 25 unless parsed_limit.positive?

        [parsed_limit, 100].min
      end

      sig { returns(Integer) }
      def offset
        parsed_offset = params[:offset].to_i
        return 0 unless parsed_offset.positive?

        parsed_offset
      end

      sig { params(enablement_type: T.any(Symbol, Integer)).returns(String) }
      def normalized_enablement_type(enablement_type)
        case enablement_type
        when :PRODUCT_ENABLEMENT_TYPE_REPO, ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_REPO
          "repo"
        when :PRODUCT_ENABLEMENT_TYPE_USER, ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_USER
          "user"
        when :PRODUCT_ENABLEMENT_TYPE_ORG, ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_ORG
          "organization"
        when :PRODUCT_ENABLEMENT_TYPE_ORG_TEAM, ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_ORG_TEAM
          "org_team"
        when :PRODUCT_ENABLEMENT_TYPE_BUSINESS_TEAM, ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_BUSINESS_TEAM
          "business_team"
        else
          enablement_type.to_s.sub(/^PRODUCT_ENABLEMENT_TYPE_/, "").downcase
        end
      end

      sig { params(product: T.any(Symbol, Integer)).returns(String) }
      def normalized_product(product)
        case product
        when :PRODUCT_GHAS, Product::PRODUCT_GHAS
          "ghas"
        when :PRODUCT_CODE_SECURITY, Product::PRODUCT_CODE_SECURITY
          "code_security"
        when :PRODUCT_SECRET_PROTECTION, Product::PRODUCT_SECRET_PROTECTION
          "secret_protection"
        when :PRODUCT_SDLC, Product::PRODUCT_SDLC
          "sdlc"
        when :PRODUCT_COPILOT, Product::PRODUCT_COPILOT
          "copilot"
        else
          product.to_s.sub(/^PRODUCT_/, "").downcase
        end
      end

      sig { returns(T.nilable(Integer)) }
      def requested_product
        PRODUCT_MAPPING[params[:product].to_s]
      end

      sig { returns(T.nilable(Integer)) }
      def requested_enablement_type
        ENABLEMENT_TYPE_MAPPING[params[:enablement_type].to_s]
      end

      sig { returns(T.nilable(Integer)) }
      def requested_source_type
        SOURCE_TYPE_MAPPING[params[:source_type].to_s]
      end

      sig { returns(T.nilable(Integer)) }
      def requested_enablement_id
        raw_enablement_id = params[:enablement_id].presence
        return nil if raw_enablement_id.blank?

        raw_enablement_id.to_i
      end

      sig { returns(T.nilable(String)) }
      def requested_source_id
        params[:source_id].presence
      end

      sig { returns(T::Boolean) }
      def valid_filters?
        valid_product? && valid_enablement_type? && valid_source_type? && valid_enablement_id?
      end

      sig { returns(T::Boolean) }
      def valid_product?
        params[:product].blank? || !requested_product.nil?
      end

      sig { returns(T::Boolean) }
      def valid_enablement_type?
        params[:enablement_type].blank? || !requested_enablement_type.nil?
      end

      sig { returns(T::Boolean) }
      def valid_source_type?
        params[:source_type].blank? || !requested_source_type.nil?
      end

      sig { returns(T::Boolean) }
      def valid_enablement_id?
        raw_enablement_id = params[:enablement_id].presence
        raw_enablement_id.blank? || /\A\d+\z/.match?(raw_enablement_id)
      end

      sig { params(timestamp: T.untyped).returns(T.nilable(String)) }
      def timestamp_to_iso8601(timestamp)
        return nil if timestamp.nil?

        Time.at(timestamp.seconds, timestamp.respond_to?(:nanos) ? timestamp.nanos / 1000 : 0, :microsecond).utc.iso8601
      end

      sig { params(error: Twirp::Error).void }
      def render_twirp_error(error)
        status = case error.code
        when :not_found
          :not_found
        when :invalid_argument
          :bad_request
        when :failed_precondition
          :unprocessable_entity
        else
          :internal_server_error
        end

        render json: { error: error.msg }, status: status
      end
    end
  end
end
