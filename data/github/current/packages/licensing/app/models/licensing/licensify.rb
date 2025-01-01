# typed: strict
# frozen_string_literal: true

require "licensify/client"

module Licensing
  module Licensify
    include Kernel

    class Error < StandardError; end
    class LicensifyRequestFailed < StandardError; end

    class LicensifyProduct < T::Enum
      enums do
        SDLC = new
        GHAS = new
        CODE_SECURITY = new
        SECRET_PROTECTION = new
      end

      sig { returns(Integer) }
      def to_proto
        case self
        when SDLC then ::Licensify::Services::V1::Product::PRODUCT_SDLC
        when GHAS then ::Licensify::Services::V1::Product::PRODUCT_GHAS
        when CODE_SECURITY then ::Licensify::Services::V1::Product::PRODUCT_CODE_SECURITY
        when SECRET_PROTECTION then ::Licensify::Services::V1::Product::PRODUCT_SECRET_PROTECTION
        end
      end

      sig { params(sku: GitHub::Turboghas::SKU).returns(LicensifyProduct) }
      def self.from_turboghas_sku(sku)
        case sku
        when GitHub::Turboghas::SKU::Bundled
          LicensifyProduct::GHAS
        when GitHub::Turboghas::SKU::CodeSecurity
          LicensifyProduct::CODE_SECURITY
        when GitHub::Turboghas::SKU::SecretSecurity
          LicensifyProduct::SECRET_PROTECTION
        end
      end
    end



    SERVICE_NAME = T.let("licensify", String)

    sig { params(timeout: T.nilable(Integer)).returns(::Licensify::Client) }
    def licensify_client(timeout: nil)
      @licensify_client ||= T.let(build_client(timeout: timeout), T.nilable(::Licensify::Client))
    end

    # Override this method to add custom tags for licensify errors.
    sig { returns(T::Hash[String, String]) }
    def licensify_error_tags
      {}
    end



    sig { params(customer_id: T.nilable(Integer), product: LicensifyProduct, enablement_reasons: T::Array[Integer]).returns(T::Array[String]) }
    def get_licensify_licensee_ids(customer_id, product:, enablement_reasons: [])
      licensify_req = ::Licensify::Services::V1::GetLicenseeIdsRequest.new(
        customerId: customer_id,
        product: product.to_proto,
        enablementReasons: enablement_reasons,
      )
      licensify_res = licensify_client.get_licensee_ids(licensify_req)
      if licensify_res.error.present?
        log_licensify_error(__method__.to_s, T.let(licensify_res.error, Twirp::Error))
        return []
      end

      licensify_res.data["licenseeIds"].to_a
    rescue Faraday::Error, Twirp::Error => e
      log_licensify_error(__method__.to_s, e)
      []
    end

    sig { params(customer_id: Integer, product: LicensifyProduct).returns(T::Array[::Licensify::Services::V1::GroupedCount]) }
    def get_licensify_grouped_counts(customer_id, product:)
      begin
        licensify_req = ::Licensify::Services::V1::GetGroupedCountsRequest.new(
          customerId: customer_id,
          products: [product.to_proto],
        )
        licensify_res = T.let(licensify_client.get_grouped_counts(licensify_req), Twirp::ClientResp[::Licensify::Services::V1::GetGroupedCountsResponse])
      rescue Faraday::Error, Twirp::Error => e
        log_licensify_error(__method__.to_s, e)
        raise LicensifyRequestFailed.new(e.message)
      end

      if licensify_res.error.present?
        licensify_error = T.must(licensify_res.error)
        log_licensify_error(__method__.to_s, licensify_error)
        raise LicensifyRequestFailed.new(licensify_error.msg)
      end

      counts = T.let([], T::Array[::Licensify::Services::V1::GroupedCount])

      licensify_res.data.productCounts.each do |product_count|
        product_count = T.let(product_count, ::Licensify::Services::V1::ProductGroupedCounts)
        returned_product = case product_count.product
        when Symbol
          ::Licensify::Services::V1::Product.resolve(T.cast(product_count.product, Symbol))
        else
          T.cast(product_count.product, Integer)
        end
        next unless returned_product == product.to_proto

        counts = counts.concat(product_count.counts.to_a)
      end

      counts
    end

    sig { params(customer_id: Integer, product: LicensifyProduct).returns(T::Array[::Licensify::Services::V1::LicenseHistoryEvent]) }
    def get_license_history(customer_id, product:)
      begin
        licensify_req = ::Licensify::Services::V1::GetLicenseHistoryRequest.new(
          customerId: customer_id,
          product: product.to_proto
        )
        licensify_res = T.let(licensify_client.get_license_history(licensify_req), Twirp::ClientResp[::Licensify::Services::V1::GetLicenseHistoryResponse])
      rescue Faraday::Error, Twirp::Error => e
        log_licensify_error(__method__.to_s, e)
        raise LicensifyRequestFailed.new(e.message)
      end

      if licensify_res.error.present?
        licensify_error = T.must(licensify_res.error)
        log_licensify_error(__method__.to_s, licensify_error)
        raise LicensifyRequestFailed.new(licensify_error.msg)
      end

      licensify_res.data.events.to_a
    end

    sig { params(location: String, error: T.any(Twirp::Error, Exception)).void }
    def log_licensify_error(location, error)
      GitHub.logger.with_named_tags(
        "code.function": location,
        **licensify_error_tags,
      ) do
        message = "Licensify communication error"
        if error.is_a?(Twirp::Error)
          GitHub.logger.error(
            message,
            {
              "exception.type": "Twirp::Error: #{error.code}",
              "exception.message": error.msg,
              "exception.stacktrace": Rails.backtrace_cleaner.clean(caller).join("\n").truncate(15000),
            },
          )
        else
          GitHub.logger.error(message, error)
        end
      end
    end

    private

    sig { params(grouped_counts: T::Array[::Licensify::Services::V1::GroupedCount], active: T.nilable(T::Boolean), server_only: T.nilable(T::Boolean), vss_linked: T.nilable(T::Boolean)).returns(Integer) }
    def filter_grouped_counts(grouped_counts, active: nil, server_only: nil, vss_linked: nil)
      grouped_counts.sum do |grouped_count|
        next 0 if !active.nil? && grouped_count.isActive != active
        next 0 if !server_only.nil? && grouped_count.serverOnly != server_only
        next 0 if !vss_linked.nil? && grouped_count.vssLinked != vss_linked
        grouped_count.count
      end
    end

    sig { params(timeout: T.nilable(Integer)).returns(::Licensify::Client) }
    def build_client(timeout: nil)
      ::Licensify::Client.new(host: GitHub.licensify_host, hmac_key: GitHub.licensify_hmac_key) do |conn|
        conn.options.timeout = timeout if !timeout.nil?
        conn.request :retry, {
          max: 2,
          interval: 0.050,
          interval_randomness: 0.5,
          backoff_factor: 1.2,
          methods: [:post],
          exceptions: [Faraday::ConnectionFailed],
          retry_block: -> (env, _, retries, exception) {
            tags = [
              "status:#{env[:status]}",
              "retries:#{retries}",
              "error:#{exception.class}",
              "path:#{env[:url].request_uri}"
            ]
            GitHub.dogstats.increment("licensify_client.retries", tags: tags)
          }
        }
        conn.use GitHub::FaradayMiddleware::RequestID
        conn.use GitHub::FaradayMiddleware::StaffRequest
        conn.use GitHub::FaradayMiddleware::TenantContext
        conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME, enable_path_tag: true
      end
    end
  end
  extend ::Licensing::Licensify
end
