# typed: true
# frozen_string_literal: true

require "monolith-twirp-licensing-customers"
require "google/protobuf/timestamp_pb"

module Api::Internal::Twirp::Licensing
  module Customers
    module V1
      # Handler for the MonolithTwirp::Licensing::Customers::V1::ProductEnablementsAPIService
      class ProductEnablementsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["licensing"]
        handles_service MonolithTwirp::Licensing::Customers::V1::ProductEnablementsAPIService

        DEFAULT_REPOS_PAGE_SIZE = 10_000

        CopilotOwner = T.type_alias { T.nilable(T.any(::Copilot::Business, ::Copilot::Organization)) }
        CopilotPlanMetadata = T.type_alias do
          {
            plan_name: T.nilable(String),
            plan_owner_type: T.nilable(Integer),
            plan_owner_id: T.nilable(Integer),
            trial_plan: T.nilable(Integer),
            trial_end_date: T.nilable(Google::Protobuf::Timestamp),
          }
        end

        # Public: Implementation of the GetProductEnablements Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse, Twirp::Error))
        end
        def get_product_enablements(req, env)
          # Validate input parameters
          if (validation_error = validate_request(req))
            return validation_error
          end

          customer = Customer.find_by(id: id_argument(req.customer_id))
          return Twirp::Error.not_found("customer not found") if customer.nil?

          if (precondition_error = validate_customer_preconditions(customer))
            return precondition_error
          end

          case req.enablement_type
          when :PRODUCT_ENABLEMENT_TYPE_REPO
            handle_repo_enablements(customer, req)
          when :PRODUCT_ENABLEMENT_TYPE_BUSINESS_TEAM
            handle_business_team_enablements(customer, req)
          when :PRODUCT_ENABLEMENT_TYPE_USER
            handle_business_user_enablements(customer, req)
          else
            Twirp::Error.invalid_argument("enablement_type not supported", argument: "enablement_type")
          end
        end

        private

        sig do
          params(
            customer: Customer,
            req: MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsRequest
          ).returns(MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse)
        end
        def handle_repo_enablements(customer, req)
          pagination_config = setup_pagination(req)
          org_ids = get_organization_ids(customer)
          repos = fetch_repositories(org_ids, pagination_config)

          product_enablements = generate_product_enablements(repos, customer, req.products.to_a)

          MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse.new(
            next_page_token: pagination_config[:next_cursor],
            product_enablements: product_enablements
          )
        end

        sig do
          params(
            customer: Customer,
            req: MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsRequest
          ).returns(MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse)
        end
        def handle_business_team_enablements(customer, req)
          pagination_config = setup_pagination(req)
          business_team_assignments = fetch_copilot_business_team_assignments(customer, pagination_config)

          product_enablements = generate_business_team_product_enablements(business_team_assignments, customer, req.products.to_a)

          MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse.new(
            next_page_token: pagination_config[:next_cursor],
            product_enablements: product_enablements
          )
        end

        sig do
          params(
            customer: Customer,
            req: MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsRequest
          ).returns(MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse)
        end
        def handle_business_user_enablements(customer, req)
          pagination_config = setup_pagination(req)
          business_user_assignments = fetch_copilot_business_user_assignments(customer, pagination_config)

          product_enablements = generate_business_user_product_enablements(business_user_assignments, customer, req.products.to_a)

          MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse.new(
            next_page_token: pagination_config[:next_cursor],
            product_enablements: product_enablements
          )
        end

        # Validates the incoming request parameters
        sig { params(req: MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsRequest).returns(T.nilable(Twirp::Error)) }
        def validate_request(req)
          unless id_argument(req.customer_id)
            return Twirp::Error.invalid_argument("customer_id is required", argument: "customer_id")
          end

          if req.products.empty?
            return Twirp::Error.invalid_argument("products is required", argument: "requested_products")
          end

          if req.enablement_type.nil?
            return Twirp::Error.invalid_argument("enablement_type is required", argument: "enablement_type")
          end

          nil
        end

        # Validates customer preconditions for the request
        sig { params(customer: Customer).returns(T.nilable(Twirp::Error)) }
        def validate_customer_preconditions(customer)
          if customer.billable_owner.nil? || customer.billable_owner.instance_of?(User)
            return Twirp::Error.failed_precondition("customer has no valid billable owner", subject: "customer_id")
          end

          nil
        end

        # Sets up pagination configuration
        sig { params(req: MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsRequest).returns(T::Hash[Symbol, T.untyped]) }
        def setup_pagination(req)
          page_size = DEFAULT_REPOS_PAGE_SIZE
          page_size = req.page_size if req.page_size.positive? && req.page_size < page_size

          if req.page_token.include?("-")
            owner_id, repo_id = req.page_token.split("-").map(&:to_i)
            compound_cursor = [owner_id, repo_id] if owner_id&.positive? && repo_id&.positive?
          else
            cursor = req.page_token.to_i
            cursor_last_id = cursor > 0 ? cursor : nil
          end

          { page_size: page_size, cursor_last_id: cursor_last_id, compound_cursor: compound_cursor, next_cursor: "" }
        end

        # Gets organization IDs for the customer
        sig { params(customer: Customer).returns(T::Array[Integer]) }
        def get_organization_ids(customer)
          if business = Business.find_by(customer_id: customer.id)
            business.organization_ids
          elsif customer.billable_owner.instance_of?(Organization)
            customer.organization_ids
          else
            []
          end
        end

        # Fetches repositories with pagination
        sig { params(org_ids: T::Array[Integer], pagination_config: T::Hash[Symbol, T.untyped]).returns(T::Array[Repository]) }
        def fetch_repositories(org_ids, pagination_config)

          if FeatureFlag.vexi.enabled?(:product_enablements_org_id_and_repo_cursor, default: false) || pagination_config[:compound_cursor]
            repo_ids, next_cursor = ::Repositories.domain.repo_ids_by_owners_at_cursor(
              owner_ids: org_ids,
              cursor: pagination_config[:compound_cursor],
              page_size: pagination_config[:page_size],
              exclude_archived: true,
              active_only: true,
              visibility: ::Repositories::RepositoryVisibility::Private,
            )

            pagination_config[:next_cursor] = next_cursor.join("-") if next_cursor
            repos = []
            if repo_ids
              repo_ids.each_slice(10_000) do |repo_id_batch|
                repos.concat(Repository.select(:id, :owner_id, :maintained, :public, :active, :source_id).where(id: repo_id_batch).to_a)
              end
            end

          else
            # Build scope for repositories owned by the organizations
            scope = Repository.select(:id, :owner_id, :maintained, :public, :active, :source_id)
                              .where(owner_id: org_ids)
                              .where(maintained: true)  # exclude_archived
                              .where(public: false)     # private_only
                              .where(active: true)      # active_only

            # Apply cursor filter
            if pagination_config[:cursor_last_id]
              scope = scope.where("repositories.id > ?", pagination_config[:cursor_last_id])
            end

            # Order by repo ID and limit (fetch one extra to check if there's a next page)
            repos = scope.order("repositories.id ASC").limit(pagination_config[:page_size] + 1).to_a

            # Handle pagination
            is_last_page = repos.size <= pagination_config[:page_size]
            unless is_last_page
              repos = repos.first(pagination_config[:page_size])  # Remove the extra record
              pagination_config[:next_cursor] = repos.last&.id&.to_s || ""
            end
          end

          # Preload configurations for performance
          Configurable.preload_configuration(repos)
          SecurityProductsEnablement::RepositorySecuritySettings.preload_settings_for(repos)

          repos
        end

        sig { params(customer: Customer, pagination_config: T::Hash[Symbol, T.untyped]).returns(T::Array[Copilot::SeatAssignment]) }
        def fetch_copilot_business_team_assignments(customer, pagination_config)
          return [] unless business = Business.find_by(customer_id: customer.id)

          scope = Copilot::SeatAssignment.business_team_assignments(business).includes(:owner)

          if pagination_config[:cursor_last_id]
            scope = scope.where("assignable_id > ?", pagination_config[:cursor_last_id])
          end

          seat_assignments = scope.order("assignable_id ASC").limit(pagination_config[:page_size] + 1).to_a

          if seat_assignments.size > pagination_config[:page_size]
            pagination_config[:next_cursor] = seat_assignments[pagination_config[:page_size] - 1]&.assignable_id&.to_s || ""
            seat_assignments = seat_assignments.first(pagination_config[:page_size])
          end

          seat_assignments
        end

        sig { params(customer: Customer, pagination_config: T::Hash[Symbol, T.untyped]).returns(T::Array[Copilot::SeatAssignment]) }
        def fetch_copilot_business_user_assignments(customer, pagination_config)
          return [] unless business = Business.find_by(customer_id: customer.id)

          scope = Copilot::SeatAssignment.for_owner(business).where(assignable_type: "User").includes(:owner)

          if pagination_config[:cursor_last_id]
            scope = scope.where("assignable_id > ?", pagination_config[:cursor_last_id])
          end

          seat_assignments = scope.order("assignable_id ASC").limit(pagination_config[:page_size] + 1).to_a

          if seat_assignments.size > pagination_config[:page_size]
            pagination_config[:next_cursor] = seat_assignments[pagination_config[:page_size] - 1]&.assignable_id&.to_s || ""
            seat_assignments = seat_assignments.first(pagination_config[:page_size])
          end

          seat_assignments
        end

        # Generates product enablements based on repository configuration
        sig do
          params(
            repos: T::Array[Repository],
            customer: Customer,
            requested_products: T::Array[T.any(Symbol, Integer)]
          ).returns(T::Array[MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse::ProductEnablement])
        end
        def generate_product_enablements(repos, customer, requested_products)
          product_enablements = []
          bundled_customer = T.must(customer.billable_owner).advanced_security_products_bundled?

          # Determine which products to check based on request
          include_ghas = requested_products.include?(:PRODUCT_GHAS)
          include_code_security = requested_products.include?(:PRODUCT_CODE_SECURITY)
          include_secret_protection = requested_products.include?(:PRODUCT_SECRET_PROTECTION)

          repos.each do |repo|
            if bundled_customer
              add_bundled_enablements(product_enablements, repo, include_ghas)
            else
              add_unbundled_enablements(product_enablements, repo, include_code_security, include_secret_protection)
            end
          end

          product_enablements
        end

        # Adds bundled product enablements (GHAS)
        sig do
          params(
            product_enablements: T::Array[MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse::ProductEnablement],
            repo: Repository,
            include_ghas: T::Boolean
          ).void
        end
        def add_bundled_enablements(product_enablements, repo, include_ghas)
          return unless include_ghas && repo.advanced_security_enabled?

          product_enablements << MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse::ProductEnablement.new(
            enablement_id: repo.id,
            enablement_type: MonolithTwirp::Licensing::Customers::V1::ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_REPO,
            product: MonolithTwirp::Licensing::Customers::V1::Product::PRODUCT_GHAS,
          )
        end

        # Adds unbundled product enablements (Code Security and Secret Protection)
        sig do
          params(
            product_enablements: T::Array[MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse::ProductEnablement],
            repo: Repository,
            include_code_security: T::Boolean,
            include_secret_protection: T::Boolean
          ).void
        end
        def add_unbundled_enablements(product_enablements, repo, include_code_security, include_secret_protection)
          # Check for Secret Protection enablement
          if include_secret_protection && SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
            product_enablements << MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse::ProductEnablement.new(
              enablement_id: repo.id,
              enablement_type: MonolithTwirp::Licensing::Customers::V1::ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_REPO,
              product: MonolithTwirp::Licensing::Customers::V1::Product::PRODUCT_SECRET_PROTECTION,
            )
          end

          # Check for Code Security enablement
          if include_code_security && SecurityProduct::CodeSecurity.new(repo).enabled?
            product_enablements << MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse::ProductEnablement.new(
              enablement_id: repo.id,
              enablement_type: MonolithTwirp::Licensing::Customers::V1::ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_REPO,
              product: MonolithTwirp::Licensing::Customers::V1::Product::PRODUCT_CODE_SECURITY,
            )
          end
        end

        # Generates product enablements based on business team Copilot seat assignments
        sig do
          params(
            seat_assignments: T::Array[Copilot::SeatAssignment],
            customer: Customer,
            requested_products: T::Array[T.any(Symbol, Integer)]
          ).returns(T::Array[MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse::ProductEnablement])
        end
        def generate_business_team_product_enablements(seat_assignments, customer, requested_products)
          product_enablements = []

          # Check if Copilot product is requested
          include_copilot = requested_products.include?(:PRODUCT_COPILOT)

          return product_enablements unless include_copilot
          return product_enablements if seat_assignments.empty?

          seat_assignments.each do |seat_assignment|
            metadata = build_copilot_plan_metadata(seat_assignment)
            product_enablements << MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse::ProductEnablement.new(
              enablement_id: seat_assignment.assignable_id,
              enablement_type: MonolithTwirp::Licensing::Customers::V1::ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_BUSINESS_TEAM,
              product: MonolithTwirp::Licensing::Customers::V1::Product::PRODUCT_COPILOT,
              is_pending_cancellation: seat_assignment.pending_cancellation?,
              plan_name: metadata[:plan_name],
              plan_owner_type: metadata[:plan_owner_type],
              plan_owner_id: metadata[:plan_owner_id],
              trial_plan: metadata[:trial_plan],
              trial_end_date: metadata[:trial_end_date],
              pending_cancellation_at: timestamp_from(seat_assignment.pending_cancellation_date),
            )
          end

          product_enablements
        end

        # Generates product enablements based on business user Copilot seat assignments
        sig do
          params(
            seat_assignments: T::Array[Copilot::SeatAssignment],
            customer: Customer,
            requested_products: T::Array[T.any(Symbol, Integer)]
          ).returns(T::Array[MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse::ProductEnablement])
        end
        def generate_business_user_product_enablements(seat_assignments, customer, requested_products)
          product_enablements = []

          # Check if Copilot product is requested
          include_copilot = requested_products.include?(:PRODUCT_COPILOT)

          return product_enablements unless include_copilot
          return product_enablements if seat_assignments.empty?

          seat_assignments.each do |seat_assignment|
            metadata = build_copilot_plan_metadata(seat_assignment)
            product_enablements << MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse::ProductEnablement.new(
              enablement_id: seat_assignment.assignable_id,
              enablement_type: MonolithTwirp::Licensing::Customers::V1::ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_USER,
              product: MonolithTwirp::Licensing::Customers::V1::Product::PRODUCT_COPILOT,
              is_pending_cancellation: seat_assignment.pending_cancellation?,
              plan_name: metadata[:plan_name],
              plan_owner_type: metadata[:plan_owner_type],
              plan_owner_id: metadata[:plan_owner_id],
              trial_plan: metadata[:trial_plan],
              trial_end_date: metadata[:trial_end_date],
              pending_cancellation_at: timestamp_from(seat_assignment.pending_cancellation_date),
            )
          end

          product_enablements
        end

        sig { params(seat_assignment: Copilot::SeatAssignment).returns(CopilotPlanMetadata) }
        def build_copilot_plan_metadata(seat_assignment)
          owner = seat_assignment.owner
          copilot_owner = copilot_owner_for(owner)

          trial_plan_name = copilot_trial_plan_name(copilot_owner)
          trial_plan_enum_value = trial_plan_enum(trial_plan_name)
          trial_end_timestamp = timestamp_from(copilot_trial_end_time(copilot_owner))

          {
            plan_name: copilot_owner&.copilot_plan,
            plan_owner_type: plan_owner_type_enum(copilot_owner),
            plan_owner_id: copilot_owner&.id,
            trial_plan: trial_plan_enum_value,
            trial_end_date: trial_end_timestamp,
          }
        end

        sig { params(owner: T.untyped).returns(CopilotOwner) }
        def copilot_owner_for(owner)
          case owner
          when ::Business
            ::Copilot::Business.new(owner)
          when ::Organization
            ::Copilot::Organization.new(owner)
          end
        end

        sig { params(copilot_owner: CopilotOwner).returns(T.nilable(Integer)) }
        def plan_owner_type_enum(copilot_owner)
          case copilot_owner
          when ::Copilot::Organization
            MonolithTwirp::Licensing::Customers::V1::PlanOwnerType::PLAN_OWNER_TYPE_ORGANIZATION
          when ::Copilot::Business
            MonolithTwirp::Licensing::Customers::V1::PlanOwnerType::PLAN_OWNER_TYPE_BUSINESS
          else
            MonolithTwirp::Licensing::Customers::V1::PlanOwnerType::PLAN_OWNER_TYPE_UNSPECIFIED
          end
        end

        sig { params(copilot_owner: CopilotOwner).returns(T.nilable(String)) }
        def copilot_trial_plan_name(copilot_owner)
          return nil unless copilot_owner.is_a?(::Copilot::Organization)
          return nil unless copilot_owner.on_free_trial?

          copilot_owner.business_trial&.copilot_plan
        end

        sig { params(plan_name: T.nilable(String)).returns(T.nilable(Integer)) }
        def trial_plan_enum(plan_name)
          return nil if plan_name.nil?

          case plan_name
          when "business"
            MonolithTwirp::Licensing::Customers::V1::TrialPlan::TRIAL_PLAN_BUSINESS
          when "enterprise"
            MonolithTwirp::Licensing::Customers::V1::TrialPlan::TRIAL_PLAN_ENTERPRISE
          else
            MonolithTwirp::Licensing::Customers::V1::TrialPlan::TRIAL_PLAN_UNSPECIFIED
          end
        end

        sig { params(copilot_owner: CopilotOwner).returns(T.nilable(Time)) }
        def copilot_trial_end_time(copilot_owner)
          return nil unless copilot_owner.is_a?(::Copilot::Organization)
          return nil unless copilot_owner.on_free_trial?

          trial_end = copilot_owner.business_trial&.ends_at
          return nil unless trial_end
          # Copilot::BusinessTrial::INACTIVE_DATE indicates an inactive trial; such trials should not be included in the response.
          return nil if trial_end.to_date == Copilot::BusinessTrial::INACTIVE_DATE

          convert_to_utc_time(trial_end)
        end

        sig do
          params(value: T.nilable(T.any(Time, Date, DateTime, ActiveSupport::TimeWithZone)))
            .returns(T.nilable(Google::Protobuf::Timestamp))
        end
        def timestamp_from(value)
          time_value = convert_to_utc_time(value)
          return nil unless time_value

          Google::Protobuf::Timestamp.new(seconds: time_value.to_i)
        end

        sig do
          params(value: T.nilable(T.any(Time, Date, DateTime, ActiveSupport::TimeWithZone)))
            .returns(T.nilable(Time))
        end
        def convert_to_utc_time(value)
          return nil unless value

          time_value = case value
          when ActiveSupport::TimeWithZone, Time
            value
          when DateTime
            value.to_time
          when Date
            if Time.zone
              Time.zone.local(value.year, value.month, value.day)
            else
              Time.utc(value.year, value.month, value.day)
            end
          end

          time_value&.utc
        end
      end
    end
  end
end
