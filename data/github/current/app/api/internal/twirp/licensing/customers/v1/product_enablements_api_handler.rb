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
            handle_user_enablements(customer, req)
          when :PRODUCT_ENABLEMENT_TYPE_ORG
            handle_org_enablements(customer, req)
          when :PRODUCT_ENABLEMENT_TYPE_ORG_TEAM
            handle_org_team_enablements(customer, req)
          else
            Twirp::Error.invalid_argument("enablement_type not supported", argument: "enablement_type")
          end
        end

        # Public: Implementation of the GetPreTrialGhasEnablements Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Licensing::Customers::V1::GetPreTrialGhasEnablementsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Licensing::Customers::V1::GetPreTrialGhasEnablementsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Licensing::Customers::V1::GetPreTrialGhasEnablementsRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Licensing::Customers::V1::GetPreTrialGhasEnablementsResponse, Twirp::Error))
        end
        def get_pre_trial_ghas_enablements(req, env)
          # Validate input parameters
          if (validation_error = validate_pre_trial_request(req))
            return validation_error
          end

          customer = Customer.find_by(id: id_argument(req.customer_id))
          return Twirp::Error.not_found("customer not found") if customer.nil?

          if (precondition_error = validate_customer_preconditions(customer))
            return precondition_error
          end

          # Cast to the expected type after validating it's not nil or User
          billable_owner = T.cast(customer.billable_owner, T.any(Organization, Business))
          sku_name = product_to_sku_name(req.product)

          count = BulkDisableService.get_pre_trial_enabled_repo_ids(billable_owner, sku_name).size

          MonolithTwirp::Licensing::Customers::V1::GetPreTrialGhasEnablementsResponse.new(
            count: count
          )
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
          repos = []

          # Fetch org-owned repositories
          if pagination_config[:owner_type] == :org
            org_ids = get_organization_ids(customer)
            repos = fetch_org_owned_repositories(org_ids, pagination_config)

            # If no more org repos and business is EMU switch to user owner type
            if pagination_config[:next_cursor].blank? && should_include_user_namespace_repos?(customer)
              pagination_config[:owner_type] = :user
              pagination_config[:cursor_last_id] = nil
              pagination_config[:compound_cursor] = nil
            end
          end

          # Fetch user namespace repositories if we're in user owner type and have capacity
          if pagination_config[:owner_type] == :user && repos.size < pagination_config[:page_size]
            remaining_size = pagination_config[:page_size] - repos.size
            user_repos = fetch_user_owned_repositories(customer, pagination_config, remaining_size)
            repos.concat(user_repos)
          end

          # Encode owner_type in next_cursor for the response
          next_page_token = build_next_page_token(pagination_config)
          product_enablements = generate_product_enablements(repos, customer, req.products.to_a)

          MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse.new(
            next_page_token: next_page_token,
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
          # Early return if Copilot is not requested to avoid unnecessary queries
          unless req.products.include?(:PRODUCT_COPILOT)
            return MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse.new(
              next_page_token: "",
              product_enablements: []
            )
          end

          pagination_config = setup_pagination(req)
          business_team_assignments = fetch_copilot_business_team_assignments(customer, pagination_config)

          product_enablements = generate_business_team_product_enablements(business_team_assignments, customer)

          MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse.new(
            next_page_token: pagination_config[:next_cursor],
            product_enablements: product_enablements
          )
        end

        # Handles user enablement requests for a customer.
        # Returns ALL user seat assignments for the customer's business, including:
        # - Users assigned at the business level (owner = Business)
        # - Users assigned at the organization level (owner = Organization, for orgs owned by the business)
        sig do
          params(
            customer: Customer,
            req: MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsRequest
          ).returns(MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse)
        end
        def handle_user_enablements(customer, req)
          # Early return if Copilot is not requested to avoid unnecessary queries
          unless req.products.include?(:PRODUCT_COPILOT)
            return MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse.new(
              next_page_token: "",
              product_enablements: []
            )
          end

          pagination_config = setup_pagination(req)
          business_user_assignments = fetch_copilot_business_user_assignments(customer, pagination_config)

          product_enablements = generate_business_user_product_enablements(business_user_assignments, customer)

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
        def handle_org_enablements(customer, req)
          # Early return if Copilot is not requested to avoid unnecessary queries
          unless req.products.include?(:PRODUCT_COPILOT)
            return MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse.new(
              next_page_token: "",
              product_enablements: []
            )
          end

          pagination_config = setup_pagination(req)
          org_assignments = fetch_copilot_org_assignments(customer, pagination_config)

          product_enablements = generate_org_product_enablements(org_assignments, customer)

          MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse.new(
            next_page_token: pagination_config[:next_cursor],
            product_enablements: product_enablements
          )
        end

        # Handles org team enablement requests for a customer.
        # Returns org team (Team) Copilot seat assignments for organizations in the customer's business.
        sig do
          params(
            customer: Customer,
            req: MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsRequest
          ).returns(MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse)
        end
        def handle_org_team_enablements(customer, req)
          # Early return if Copilot is not requested to avoid unnecessary queries
          unless req.products.include?(:PRODUCT_COPILOT)
            return MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse.new(
              next_page_token: "",
              product_enablements: []
            )
          end

          pagination_config = setup_pagination(req)
          org_team_assignments = fetch_copilot_org_team_assignments(customer, pagination_config)

          product_enablements = generate_org_team_product_enablements(org_team_assignments, customer)

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

        # Validates the incoming pre-trial request parameters
        sig { params(req: MonolithTwirp::Licensing::Customers::V1::GetPreTrialGhasEnablementsRequest).returns(T.nilable(Twirp::Error)) }
        def validate_pre_trial_request(req)
          unless id_argument(req.customer_id)
            return Twirp::Error.invalid_argument("customer_id is required", argument: "customer_id")
          end

          valid_products = [:PRODUCT_CODE_SECURITY, :PRODUCT_SECRET_PROTECTION]
          unless valid_products.include?(req.product)
            return Twirp::Error.invalid_argument("product must be PRODUCT_CODE_SECURITY or PRODUCT_SECRET_PROTECTION", argument: "product")
          end

          nil
        end

        # Maps product enum to SKU name for database queries
        sig { params(product: T.any(Symbol, Integer)).returns(String) }
        def product_to_sku_name(product)
          case product
          when :PRODUCT_CODE_SECURITY, MonolithTwirp::Licensing::Customers::V1::Product::PRODUCT_CODE_SECURITY
            "code_security"
          when :PRODUCT_SECRET_PROTECTION, MonolithTwirp::Licensing::Customers::V1::Product::PRODUCT_SECRET_PROTECTION
            "secret_protection"
          else
            raise ArgumentError, "Unexpected product value #{product.inspect} in product_to_sku_name; this should have been rejected by validate_pre_trial_request"
          end
        end

        # Sets up pagination configuration
        sig { params(req: MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsRequest).returns(T::Hash[Symbol, T.untyped]) }
        def setup_pagination(req)
          page_size = DEFAULT_REPOS_PAGE_SIZE
          page_size = req.page_size if req.page_size.positive? && req.page_size < page_size

          # Parse owner_type prefix from token (defaults to :org for backwards compatibility)
          owner_type = :org
          token = req.page_token
          if token.start_with?("user:")
            owner_type = :user
            token = token.delete_prefix("user:")
          elsif token.start_with?("org:")
            token = token.delete_prefix("org:")
          end

          if token.include?("-")
            owner_id, repo_id = token.split("-").map(&:to_i)
            compound_cursor = [owner_id, repo_id] if owner_id&.positive? && repo_id&.positive?
          else
            cursor = token.to_i
            cursor_last_id = cursor > 0 ? cursor : nil
          end

          { page_size: page_size, cursor_last_id: cursor_last_id, compound_cursor: compound_cursor, next_cursor: "", owner_type: owner_type }
        end

        # Gets organization owner ids for the customer.
        # User namespace repos are handled separately via fetch_user_owned_repositories for performance.
        sig { params(customer: Customer).returns(T::Array[Integer]) }
        def get_organization_ids(customer)
          if business = customer.business
            business.organization_ids
          elsif customer.billable_owner.instance_of?(Organization)
            customer.organization_ids
          else
            []
          end
        end

        # Checks if user namespace repositories should be included for this customer's business
        sig { params(customer: Customer).returns(T::Boolean) }
        def should_include_user_namespace_repos?(customer)
          business = customer.business
          return false unless business
          business.enterprise_managed?
        end

        # Builds the next page token with owner_type prefix
        sig { params(pagination_config: T::Hash[Symbol, T.untyped]).returns(String) }
        def build_next_page_token(pagination_config)
          return "" if pagination_config[:next_cursor].blank?

          owner_type_prefix = pagination_config[:owner_type] == :user ? "user:" : "org:"
          "#{owner_type_prefix}#{pagination_config[:next_cursor]}"
        end

        # Fetches org owned repositories with pagination
        sig { params(org_ids: T::Array[Integer], pagination_config: T::Hash[Symbol, T.untyped]).returns(T::Array[Repository]) }
        def fetch_org_owned_repositories(org_ids, pagination_config)
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

          # Preload configurations for performance
          Configurable.preload_configuration(repos)
          SecurityProductsEnablement::RepositorySecuritySettings.preload_settings_for(repos)

          repos
        end

        # Fetches user owned repositories with pagination
        sig { params(customer: Customer, pagination_config: T::Hash[Symbol, T.untyped], limit: Integer).returns(T::Array[Repository]) }
        def fetch_user_owned_repositories(customer, pagination_config, limit)
          business = customer.business
          return [] unless business

          repo_ids = business.write_through_cache.get_and_update(:user_namespace_repositories_ids) || []
          return [] if repo_ids.empty?

          # Sort first, then apply cursor filter for correct pagination
          repo_ids = repo_ids.sort

          # Apply cursor filter
          if pagination_config[:cursor_last_id]
            repo_ids = repo_ids.select { |id| id > pagination_config[:cursor_last_id] }
          end

          # Paginate (fetch one extra to check for next page)
          repo_ids = repo_ids.first(limit + 1)

          # Handle pagination
          if repo_ids.size > limit
            pagination_config[:next_cursor] = repo_ids[limit - 1].to_s
            repo_ids = repo_ids.first(limit)
          else
            pagination_config[:next_cursor] = ""
          end

          return [] if repo_ids.empty?

          repos = []
          repo_ids.each_slice(10_000) do |repo_id_batch|
            repos.concat(Repository.select(:id, :owner_id, :maintained, :public, :active, :source_id)
              .where(id: repo_id_batch, maintained: true, public: false, active: true).to_a)
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

          # Get seat assignments for the business
          scope = Copilot::SeatAssignment
            .where(assignable_type: "User", owner_type: "Business", owner_id: business.id)

          # Also include seat assignments for all organizations owned by the business
          org_ids = business.organization_ids
          if org_ids.any?
            scope = scope.or(
              Copilot::SeatAssignment.where(assignable_type: "User", owner_type: "Organization", owner_id: org_ids)
            )
          end

          scope = scope.includes(:owner)

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
        def fetch_copilot_org_team_assignments(customer, pagination_config)
          org_ids = get_organization_ids(customer)
          return [] if org_ids.empty?

          # Get org team (Team) seat assignments for organizations in the customer
          scope = Copilot::SeatAssignment
            .where(assignable_type: "Team", owner_type: "Organization", owner_id: org_ids)
            .includes(:owner)

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
        def fetch_copilot_org_assignments(customer, pagination_config)
          org_ids = get_organization_ids(customer)
          return [] if org_ids.empty?

          # Get org-wide seat assignments where the assignable is the organization itself
          scope = Copilot::SeatAssignment
            .where(assignable_type: "Organization", owner_type: "Organization", owner_id: org_ids, assignable_id: org_ids)
            .includes(:owner)

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
          ).returns(T::Array[MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse::ProductEnablement])
        end
        def generate_business_team_product_enablements(seat_assignments, customer)
          product_enablements = []

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
          ).returns(T::Array[MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse::ProductEnablement])
        end
        def generate_business_user_product_enablements(seat_assignments, customer)
          product_enablements = []

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

        # Generates product enablements based on org-wide Copilot seat assignments
        sig do
          params(
            seat_assignments: T::Array[Copilot::SeatAssignment],
            customer: Customer,
          ).returns(T::Array[MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse::ProductEnablement])
        end
        def generate_org_product_enablements(seat_assignments, customer)
          product_enablements = []

          return product_enablements if seat_assignments.empty?

          seat_assignments.each do |seat_assignment|
            metadata = build_copilot_plan_metadata(seat_assignment)
            product_enablements << MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse::ProductEnablement.new(
              enablement_id: seat_assignment.assignable_id,
              enablement_type: MonolithTwirp::Licensing::Customers::V1::ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_ORG,
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

        # Generates product enablements based on org team Copilot seat assignments
        sig do
          params(
            seat_assignments: T::Array[Copilot::SeatAssignment],
            customer: Customer,
          ).returns(T::Array[MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse::ProductEnablement])
        end
        def generate_org_team_product_enablements(seat_assignments, customer)
          product_enablements = []

          return product_enablements if seat_assignments.empty?

          seat_assignments.each do |seat_assignment|
            metadata = build_copilot_plan_metadata(seat_assignment)
            product_enablements << MonolithTwirp::Licensing::Customers::V1::GetProductEnablementsResponse::ProductEnablement.new(
              enablement_id: seat_assignment.assignable_id,
              enablement_type: MonolithTwirp::Licensing::Customers::V1::ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_ORG_TEAM,
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
