# typed: strict
# frozen_string_literal: true

require "meuse/client"

# This class is a wrapper around the yet-to-be-built Billing API Client
# Reference for mock data: https://github.com/github/gitcoin/discussions/6694#discussioncomment-611375
module Billing
  module Api
    class ClientWrapper

      class BillingClientError < StandardError

        sig { returns(T.untyped) }
        attr_reader :original_error

        sig { returns(T::Boolean) }
        def has_error?
          true
        end

        sig { params(message: String, original_error: T.untyped).void }
        def initialize(message, original_error: nil)
          super(message)
          @original_error = original_error
          set_backtrace caller
        end
      end

      ListAccountUsageResponseType = T.type_alias do
        T.any(T.all(T::Hash[Symbol, T.untyped], ListAccountUsageMethods), T.all(BillingClientError, ListAccountUsageMethods))
      end

      ListProductUsageResponseType = T.type_alias do
        T.any(T.all(T::Hash[Symbol, T.untyped], ListProductUsageMethods), T.all(BillingClientError, ListProductUsageMethods))
      end

      MAX_RETRIES = 7
      RETRYABLE_ERRORS = T.let([
        Errno::ECONNREFUSED,
        Errno::ECONNRESET,
        Errno::ETIMEDOUT,
        Faraday::ConnectionFailed,
        Faraday::TimeoutError,
        Net::HTTPRequestTimeOut,
        Net::ReadTimeout,
        Twirp::Error
      ].freeze, T::Array[T.untyped])

      MEUSE_SERVICE_NAME = "meuse"
      PRODUCT_CATALOG_CACHE_KEY = "billing.api.product_catalog.all_products"

      CODESPACES_STORAGE_SKUS = T.let({
        storage: "Storage",
        prebuild_storage: "Prebuild Storage"
      }.freeze, T::Hash[Symbol, String])

      CODESPACES_COMPUTE_SKUS = T.let({
        compute_d2: ::Codespaces::Skus.sku_by_name(:basicLinux32gb).display_cpus,
        compute_d4: ::Codespaces::Skus.sku_by_name(:standardLinux32gb).display_cpus,
        compute_d8: ::Codespaces::Skus.sku_by_name(:premiumLinux).display_cpus,
        compute_d16: ::Codespaces::Skus.sku_by_name(:largePremiumLinux).display_cpus,
        compute_d32: ::Codespaces::Skus.sku_by_name(:xLargePremiumLinux).display_cpus,
      }.freeze, T::Hash[Symbol, String])

      CODESPACES_SKUS = T.let(CODESPACES_COMPUTE_SKUS.merge(CODESPACES_STORAGE_SKUS), T::Hash[Symbol, String])

      MEUSE_PRODUCT_NAMES = T.let({
        actions: "actions",
        packages: "packages",
        shared_storage: "shared_storage",
        codespaces: "codespaces",
        copilot: "copilot",
        ghec: "ghec",
      }.freeze, T::Hash[Symbol, String])

      sig { returns(String) }
      def self.product_catalog_cache_key
        PRODUCT_CATALOG_CACHE_KEY
      end

      sig { params(sku: T.nilable(T.any(String, Symbol))).returns(T.nilable(String)) }
      def self.sku_name_to_label(sku)
        return unless sku

        CODESPACES_SKUS[sku.to_sym]
      end

      sig { returns(T.nilable(::Billing::Types::Account)) }
      attr_reader :billable_owner

      sig { returns(T.nilable(::Billing::Types::Account)) }
      attr_reader :owner

      sig { returns(T.nilable(::User)) }
      attr_reader :actor

      sig { returns(T.nilable(Integer)) }
      attr_reader :timeout

      sig { returns(Meuse::Client) }
      attr_reader :meuse_client

      sig { params(billable_owner: T.nilable(::Billing::Types::Account), owner: T.nilable(::Billing::Types::Account), actor: T.nilable(::User), timeout: T.nilable(Integer)).void }
      def initialize(billable_owner: nil, owner: nil, actor: nil, timeout: nil)
        @billable_owner = billable_owner
        @owner = owner
        @actor = actor
        @timeout = timeout
        @meuse_client = T.let(Meuse::Client.new(secret_key: GitHub.meuse_hmac_secret_key) do |conn|
          conn.options.timeout = timeout if !timeout.nil?
          conn.request :retry, retry_options
          conn.use GitHub::FaradayMiddleware::RequestID
          conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: MEUSE_SERVICE_NAME
          conn.use Billing::Api::ShedMiddlewareWrapper
        end, Meuse::Client)
      end

      sig { returns(T::Array[String]) }
      def codespaces_skus
        CODESPACES_SKUS.keys.map(&:to_s)
      end

      sig { returns(T::Array[String]) }
      def compute_skus
        codespaces_skus.select do |elem|
          elem.include?("compute")
        end
      end

      sig { returns(ListProductUsageResponseType) }
      def codespaces_monthly_usage
        filters = {
          budget_group: codespaces_budget_group
        }
        T.cast(list_product_usage(billable_owner&.current_metered_billing_cycle_starts_at, **filters).extend(ListProductUsageMethods), ListProductUsageResponseType)
      end

      sig { params(starts_at: T.nilable(T.any(Time, Google::Protobuf::Timestamp))).returns(T.any(T::Hash[Symbol, T.untyped], BillingClientError)) }
      def actions_monthly_usage(starts_at: nil)
        starts_at ||= billable_owner&.current_metered_billing_cycle_starts_at
        filters = {
          budget_group: shared_budget_group
        }
        list_product_usage(starts_at, **filters)
      end

      sig { returns(ListAccountUsageResponseType) }
      def codespaces_monthly_usage_by_owner
        filters = {
          budget_group: codespaces_budget_group
        }
        T.cast(list_account_usage(billable_owner&.current_metered_billing_cycle_starts_at, **filters).extend(ListAccountUsageMethods), ListAccountUsageResponseType)
      end

      sig { returns(ListProductUsageResponseType) }
      def copilot_monthly_usage
        filters = {
          product_names: [MEUSE_PRODUCT_NAMES[:copilot]]
        }
        T.cast(list_product_usage(billable_owner&.current_metered_billing_cycle_starts_at, **filters).extend(ListProductUsageMethods), ListProductUsageResponseType)
      end

      sig { returns(ListAccountUsageResponseType) }
      def copilot_monthly_usage_by_owner
        filters = {
          product_names: [MEUSE_PRODUCT_NAMES[:copilot]]
        }
        T.cast(list_account_usage(billable_owner&.current_metered_billing_cycle_starts_at, **filters).extend(ListAccountUsageMethods), ListAccountUsageResponseType)
      end

      sig { returns(ListProductUsageResponseType) }
      def ghec_monthly_usage
        filters = {
          product_names: [MEUSE_PRODUCT_NAMES[:ghec]]
        }
        T.cast(list_product_usage(billable_owner&.current_metered_billing_cycle_starts_at, **filters).extend(ListProductUsageMethods), ListProductUsageResponseType)
      end

      sig { params(usage_start: T.any(Time, Google::Protobuf::Timestamp), filters: T.untyped).returns(T.any(T::Hash[Symbol, T.untyped], BillingClientError)) }
      def list_account_usage(usage_start, **filters)
        request_params = {
          **billable_owner_request_params,
          usage_starts_at: Google::Protobuf::Timestamp.new(seconds: usage_start.to_i, nanos: 0),
          usage_ends_at: filters[:usage_ends_at] ? Google::Protobuf::Timestamp.new(seconds: filters[:usage_ends_at].to_i, nanos: 0) : nil,
          budget_group: filters[:budget_group],
          product_names: filters[:product_names],
        }.compact

        response = meuse_client.list_account_usage(request_params)

        if response.error.nil?
          response.data.to_h
        else
          log_error_and_return(error: response.error, method: __method__.to_s, request_params: request_params)
        end
      rescue => e # rubocop:todo Lint/GenericRescue
        log_error_and_return(error: e, method: __method__.to_s, request_params: request_params)
      end

      sig { params(usage_start: T.any(Time, Google::Protobuf::Timestamp), filters: T.untyped).returns(T.any(T::Hash[Symbol, T.untyped], BillingClientError)) }
      def list_product_usage(usage_start, **filters)
        request_params = {
          **billable_owner_request_params,
          **owner_request_params,
          usage_starts_at: Google::Protobuf::Timestamp.new(seconds: usage_start.to_i, nanos: 0),
          usage_ends_at: filters[:usage_ends_at] ? Google::Protobuf::Timestamp.new(seconds: filters[:usage_ends_at].to_i, nanos: 0) : nil,
          per_page: filters[:per_page],
          budget_group: filters[:budget_group],
          product_names: filters[:product_names],
          actor_id: filters[:actor_id]
        }.compact

        response = meuse_client.list_product_usage(request_params)

        if response.error.nil?
          response.data.to_h
        else
          log_error_and_return(error: response.error, method: __method__.to_s, request_params: request_params)
        end
      rescue => e # rubocop:todo Lint/GenericRescue
        log_error_and_return(error: e, method: __method__.to_s, request_params: request_params)
      end

      sig { params(product_names: T::Array[String]).returns(T.any(T::Hash[Symbol, T.untyped], BillingClientError)) }
      def get_usage_breakdown(product_names:)
        request_params = {
          customer_id: billable_owner&.customer&.id,
          entitlement_plan_name: billable_owner&.plan&.entitlement_plan_name,
          product_names: product_names,
        }

        response = meuse_client.get_usage_breakdown(request_params)

        if response.error.nil?
          response.data.to_h
        else
          log_error_and_return(error: response.error, method: __method__.to_s, request_params: request_params)
        end
      rescue ArgumentError
        raise
      rescue => e # rubocop:todo Lint/GenericRescue
        log_error_and_return(error: e, method: __method__.to_s, request_params: T.must(request_params))
      end

      sig { params(plan_name: String, entitlement_names: T::Array[String], as_of: T.nilable(T.any(Time, Google::Protobuf::Timestamp))).returns(T.any(T::Hash[Symbol, T.untyped], BillingClientError)) }
      def get_entitlement_plans(plan_name:, entitlement_names: [], as_of: nil)
        request_params = {
          plan_name: plan_name,
          entitlement_names: entitlement_names,
          customer_id: billable_owner&.customer&.id,
          as_of: as_of,
        }

        begin
          response = meuse_client.get_entitlement_plans(request_params)

          if response.error.nil?
            response.data.to_h
          else
            log_error_and_return(error: response.error, method: __method__.to_s, request_params: request_params)
          end
        rescue Faraday::ConnectionFailed => e
          log_error_and_return(error: e, method: __method__.to_s, request_params: request_params)
        end
      end

      sig { params(proposed_usage: T::Array[T::Hash[Symbol, T.untyped]], metered_cycle_start: Google::Protobuf::Timestamp).returns(T.any(T::Hash[Symbol, T.untyped], BillingClientError)) }
      def calculate_usage_quotes(proposed_usage, metered_cycle_start)
        unless metered_cycle_start.instance_of?(Google::Protobuf::Timestamp)
          raise ArgumentError, "Invalid metered_cycle_start_at! Must be a Google::Protobuf::Timestamp"
        end

        request_params = {
          proposed_usage: proposed_usage,
          metered_cycle_starts_at: metered_cycle_start,
          **billable_owner_request_params,
          **owner_request_params,
        }

        response = meuse_client.calculate_usage_quotes(request_params)

        if response.error.nil?
          wrapped_response = response.data.to_h
          wrapped_response[:usage_quotes] = wrapped_response[:usage_quotes].map { |quote| Billing::Usage::UsageQuote.new(quote) }
          wrapped_response
        else
          log_error_and_return(error: response.error, method: __method__.to_s, request_params: request_params)
        end
      rescue ArgumentError
        raise
      rescue => e # rubocop:todo Lint/GenericRescue
        log_error_and_return(error: e, method: __method__.to_s, request_params: T.must(request_params))
      end

      sig { params(earliest_usage_cutoff: Google::Protobuf::Timestamp).returns(T.any(T::Hash[Symbol, T.untyped], BillingClientError)) }
      def update_submission_details(earliest_usage_cutoff)
        request_params = {
          earliest_usage_cutoff: earliest_usage_cutoff,
          **billable_owner_request_params,
        }

        response = meuse_client.update_submission_details(request_params)

        if response.error.nil?
          response.data.to_h
        else
          log_error_and_return(error: response.error, method: __method__.to_s, request_params: request_params)
        end
      end

      # allow_partial_result: – If false (default), the API will return an error if any of the page requests fails.
      #                         If true, this method returns a partial list of line items
      #                         if subsequent page request fails after some successful ones.
      # additional_retries: - If false (default), the API will only retry according to the global configuration.
      #                       If true, the API will retry up to MAX_RETRIES on all RETRYABLE_ERRORS.
      sig do
        params(
          product_name: T.nilable(String),
          allow_partial_result: T::Boolean,
          additional_retries: T::Boolean,
          filters: T.untyped
        ).returns(T.any(T::Array[::Meuse::Services::V1::Messages::UsageLineItem], BillingClientError))
      end
      def get_usage_line_items(product_name:, allow_partial_result: false, additional_retries: false, **filters)
        request_params = {
          **billable_owner_request_params,
          **owner_request_params,
          usage_starts_at: filters[:usage_starts_at] ? Google::Protobuf::Timestamp.new(seconds: filters[:usage_starts_at].to_i, nanos: 0) : nil,
          usage_ends_at: filters[:usage_ends_at] ? Google::Protobuf::Timestamp.new(seconds: filters[:usage_ends_at].to_i, nanos: 0) : nil,
          product_name: product_name,
          product_id: filters[:product_id],
          submission_state: filters[:submission_state],
          submission_state_reason: filters[:submission_state_reason],
          custom_fields: filters[:custom_fields],
          cursor_usage_at: nil,
          cursor_id: 0,
          per_page: filters[:per_page],
          page: filters[:page]
        }.compact

        response = T.let(nil, T.nilable(Meuse::Services::V1::GetUsageLineItemsResponse))
        all_usage_line_items = T.let([], T::Array[::Meuse::Services::V1::Messages::UsageLineItem])

        begin
          loop do
            twirp_retries = 0
            response = meuse_client.get_usage_line_items(request_params)

            if additional_retries
              while response.error.class.in?(RETRYABLE_ERRORS) && ((twirp_retries += 1) < MAX_RETRIES)
                response = meuse_client.get_usage_line_items(request_params)
              end

              GitHub.dogstats.increment("billing.client.twirp_retries", tags: [
                "retries:#{twirp_retries}"
              ])
            end

            break if response.error.present?

            all_usage_line_items += response.data.usage_line_items.to_a

            break if response.data.pagination.next_page.zero?

            request_params[:page] = response.data.pagination.next_page
            request_params[:per_page] = response.data.pagination.per_page
            request_params[:cursor_usage_at] = response.data.pagination.cursor_usage_at
            request_params[:cursor_id] = response.data.pagination.cursor_id
            request_params[:product_id] = all_usage_line_items.first.product_id
          end

          if response.error.nil?
            all_usage_line_items
          elsif all_usage_line_items.present? && allow_partial_result
            log_error_and_return(error: response.error, method: __method__.to_s, request_params: request_params)
            all_usage_line_items
          else
            log_error_and_return(error: response.error, method: __method__.to_s, request_params: request_params)
          end
        rescue => e # rubocop:todo Lint/GenericRescue
          if additional_retries
            rescue_retries ||= 0
            if e.class.in?(RETRYABLE_ERRORS) && ((rescue_retries += 1) < MAX_RETRIES)
              GitHub.dogstats.increment("billing.client.rescue_retries", tags: [
                "retry_attempt:#{rescue_retries}",
                "billable_owner_id:#{billable_owner_request_params[:billable_owner_id]}",
                "billable_owner_type:#{billable_owner_request_params[:billable_owner_type]}"
              ])

              retry
            end
          end

          log_error_and_return(error: e, method: __method__.to_s, request_params: request_params)
        end
      end

      private

      sig { returns(Symbol) }
      def codespaces_budget_group
        :CODESPACES
      end

      sig { returns(Symbol) }
      def shared_budget_group
        :SHARED
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def billable_owner_request_params
        {
          billable_owner_id: billable_owner&.id,
          billable_owner_type: billable_owner&.is_a?(Business) ? "OWNER_TYPE_BUSINESS" : "OWNER_TYPE_USER",
        }
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def owner_request_params
        {
          owner_id: owner&.id,
          owner_type: owner&.is_a?(Business) ? "OWNER_TYPE_BUSINESS" : "OWNER_TYPE_USER"
        }
      end

      sig { params(error: T.untyped, method: String, request_params: T::Hash[Symbol, T.untyped]).returns(BillingClientError) }
      def log_error_and_return(error:, method:, request_params:)
        GitHub.dogstats.increment("billing.client.error", tags: ["method:#{method}", "error:#{error.class.name.to_s.underscore.parameterize}"])

        if error.is_a?(Twirp::Error)
          twirp_error_code = error.code
        end

        client_error = BillingClientError.new("Failed to request #{method}.\n\nError:\n #{error}", original_error: error)
        GitHub.logger.error({
          exception: client_error,
          "code.function": "billing.client.#{method}",
          "gh.billing.client.request_params": request_params,
          "gh.billing.client.original_error": error.to_s
        })
        Failbot.report(client_error, { "http.status_code" => twirp_error_code, "http.method" => method })
        client_error
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def retry_options
        {
          max: 2,
          interval: 0.050,
          interval_randomness: 0.5,
          backoff_factor: 1.2,
          methods: [:post],
          exceptions: [Faraday::ConnectionFailed],
          retry_block: retry_proc,
        }
      end

      sig { returns(T.proc.params(env: T::Hash[Symbol, T.untyped], arg1: T.untyped, retries: Integer, exception: T.untyped).void) }
      def retry_proc
        proc do |env, _, retries, exception|
          tags = [
            "status:#{env[:status]}",
            "retries:#{retries}",
            "rpc:#{env[:url].request_uri.sub('/twirp/', '')}",
            "error:#{exception.class}",
          ]
          GitHub.dogstats.increment("billing.client.retry", tags: tags)
        end
      end
    end
  end
end
