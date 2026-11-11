# typed: strict
# frozen_string_literal: true

module FeatureManagement
  # A client for interacting with the Feature Management Lite service. It is primarily used in the Devtools Feature Flag UI.
  class FeatureManagementLiteClient
    include GitHub::Memoizer

    # Creates a management client. timeout and open_timeout are in seconds.
    sig { params(timeout: Float, open_timeout: Float, max_retries: Integer).void }
    def initialize(timeout: 3.0, open_timeout: 1.0, max_retries: 2)
      @timeout = T.let(timeout, Float)
      @open_timeout = T.let(open_timeout, Float)
      @max_retries = T.let(max_retries, Integer)
    end

    sig { returns(FeatureManagement::FeatureFlags::Management::V4::FeatureFlagsClient) }
    memoize def client
      fm_lite_url = GitHub.feature_management_feature_flag_hub_url # In non-prod environment, this should point to fm-Lite url.
      fm_lite_conn = fm_lite_management_connection(fm_lite_url)
      FeatureManagement::FeatureFlags::Management::V4::FeatureFlagsClient.new(fm_lite_conn)
    end

    sig { params(url: String).returns(GitHub::FaradayClient::Internal) }
    private def fm_lite_management_connection(url)
      service_name = "feature_management_lite"

      GitHub::FaradayClient::Internal.new(url) do |conn|
        conn.options[:open_timeout] = @open_timeout
        conn.options[:timeout]      = @timeout

        conn.request :json
        conn.request :retry,
        max: @max_retries,
        backoff_factor:      1.2,
        methods:     [:post],
        retry_block: proc {}

        conn.use ::GitHub::FaradayMiddleware::RequestID
        conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: service_name, custom_tags: ["service_endpoint:#{url}"]
        conn.use ::FeatureManagement::VexiManagementUser
        conn.use ::GitHub::FaradayMiddleware::Resilient, name: service_name
        conn.adapter :typhoeus
      end
    end

    sig { params(page: Integer, page_size: Integer, name_filter: T.nilable(String), order_by: T.nilable(String)).returns(T::Hash[Symbol, T.untyped]) }
    def list_feature_flags(page: 1, page_size: 25, name_filter: nil, order_by: nil)
      request = FeatureManagement::FeatureFlags::Management::V4::ListFeatureFlagsRequest.new
      if name_filter.present?
        filter = FeatureManagement::FeatureFlags::Management::V4::ListFeatureFlagsFilter.new
        filter.name = name_filter
        request.filter = filter
      end
      request.page_size = page_size
      request.page = page
      request.order_by = order_by if order_by.present?

      resp = client.list_feature_flags(request)

      error = resp.error
      raise FeatureManagement::FeatureManagementLiteError.new(error.code, error.msg) if error

      # This number is an approximation since we don't have a total count API to call.
      # We need a number though for the pagination component.
      total_count = resp.data.total_pages * page_size

      {
        features: resp.data.features.to_a,
        total_count: total_count,
        current_page: resp.data.page,
        total_pages: resp.data.total_pages
      }
    end

    sig { params(name: String).returns(T.nilable(FeatureManagement::FeatureFlags::Management::V4::FeatureFlag)) }
    def get_feature_flag(name)
      if name.blank?
        return nil
      end

      request = FeatureManagement::FeatureFlags::Management::V4::GetFeatureFlagRequest.new
      request.name = name

      resp = client.get_feature_flag(request)

      error = resp.error
      if error && error.code != :not_found
        raise FeatureManagement::FeatureManagementLiteError.new(error.code, error.msg) if error
      end

      resp.data
    end

    sig { params(name: String).void }
    def delete_feature_flag(name)
      request = FeatureManagement::FeatureFlags::Management::V4::DeleteFeatureFlagRequest.new
      request.name = name

      resp = client.delete_feature_flag(request)

      error = resp.error
      raise FeatureManagement::FeatureManagementLiteError.new(error.code, error.msg) if error
    end
  end
end
