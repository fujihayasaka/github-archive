# typed: strict
# frozen_string_literal: true

# Builds the entitlements payload returned by Spark::EntitlementsController#show
# for a given user. Extracted so it can also be rendered from stafftools for
# debugging without going through an HTTP request.
class Workbench::Entitlements
  include GitHub::Memoizer
  include CopilotChatHelper

  BILLING_PLATFORM_SERVICE_NAME = "billing-platform"
  private_constant :BILLING_PLATFORM_SERVICE_NAME

  # Available statuses and docs can be found here: https://github.com/github/billing-platform/blob/main/docs/reference/features/can-proceed-with-usage.md#can-proceed-statuses
  CanProceedWithUsageResponse = T.type_alias do
    {
      canProceed: T::Boolean,
      status: String,
    }
  end

  sig { params(user: ::User).void }
  def initialize(user)
    @user = user
  end

  sig { override.returns(T.nilable(::User)) }
  def current_user
    @user
  end

  sig { override.returns(T.nilable(T.any(::Copilot::User, ::Copilot::Public::User))) }
  memoize def current_copilot_user_v2
    ::Copilot::Public::User.for(@user)
  end

  sig { returns(T::Hash[Symbol, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
  def to_h
    copilot_result = T.let({ licenseType: license_type }, T::Hash[Symbol, T.untyped]) # rubocop:disable Sorbet/ForbidTUntyped
    quotas = user_quotas
    copilot_result[:quotas] = quotas if quotas
    plan = user_plan
    copilot_result[:plan] = plan if plan

    {
      copilot: copilot_result,
      codespaces_compute: codespaces_compute_result,
      codespaces_sessions: codespaces_sessions_result,
      billing_status: billing_status,
      user_status: user_permissions_status,
    }
  end

  sig { params(_options: T.untyped).returns(T::Hash[Symbol, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
  def as_json(*_options)
    to_h
  end

  private

  sig { returns(T::Hash[Symbol, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
  def codespaces_compute_result
    checker = ::Codespaces::Access::SparkWorkbenchUsageChecker.new(@user)
    {
      allowed: checker.perform.allowed?,
      quotas: checker.user_quotas,
    }
  end

  sig { returns(T::Hash[Symbol, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
  def codespaces_sessions_result
    policy = ::Codespaces::SparkWorkbenchConcurrencyPolicy.new(@user, billable_owner: @user)
    {
      allowed: policy.has_capacity?,
    }
  end

  sig { returns(::Copilot::Public::User) }
  def copilot_user
    T.cast(current_copilot_user_v2, ::Copilot::Public::User)
  end

  sig { returns(CanProceedWithUsageResponse) }
  def billing_status
    if !copilot_user.provider_customer_id
      if copilot_user.copilot_provider.present?
        return { canProceed: false, status: "MissingCustomer" }
      else
        return { canProceed: true, status: "UsageAllowed" }
      end
    end

    entity_detail = {
      customerId: copilot_user.provider_customer_id.to_s,
      actorId: copilot_user.user.id,
    }
    if copilot_user.copilot_provider.present? && copilot_user.copilot_provider.is_a?(::Copilot::Organization)
      entity_detail[:ownerId] = copilot_user.copilot_provider.id
    end
    begin
      cpwu_response = billing_platform_client.can_proceed_with_usage(
        usageKey: {
          sku: "spark_premium_request",
          product: "spark",
          entityDetail: entity_detail,
        },
      )
    rescue Faraday::Error => e
      # Twirp::Client doesn't rescue Faraday transport errors (timeouts,
      # connection failures, etc.), so they would otherwise propagate and
      # bypass the fail-open behavior below. Treat them as an error response
      # so we still emit telemetry/Failbot reporting and fail open.
      Failbot.report(
        StandardError.new(
          "billing/can_proceed_with_usage failed: #{e.class}: #{e.message}",
        ),
      )
      http_status = e.response_status if e.respond_to?(:response_status)
      http_status ||= case e
      when Faraday::TimeoutError then 504
      else 503
      end
      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:#{http_status}", "operation:billing/can_proceed_with_usage"])
      return { canProceed: true, status: "UsageAllowed" }
    end

    if cpwu_response.error.present?
      error_details = cpwu_response.error.to_h
      Failbot.report(
        StandardError.new(
          "billing/can_proceed_with_usage failed: #{error_details.inspect}",
        ),
      )
      meta = cpwu_response.error.meta || {}
      http_status = meta[:status_code].to_i if meta[:status_code].present?
      http_status = nil if http_status == 0
      http_status ||= Twirp::ERROR_CODES_TO_HTTP_STATUS[cpwu_response.error.code] || 503
      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:#{http_status}", "operation:billing/can_proceed_with_usage"])
      { canProceed: true, status: "UsageAllowed" }
    else
      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/can_proceed_with_usage"])
      data = cpwu_response.data.to_h
      { canProceed: !!data[:canProceed], status: data[:status].to_s }
    end
  end

  sig { returns(T::Hash[Symbol, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
  def user_permissions_status
    provider = copilot_user.copilot_provider
    url = nil

    if provider.is_a?(::Copilot::Business)
      url = Rails.application.routes.url_helpers.settings_billing_enterprise_path(provider)
    elsif provider.is_a?(::Copilot::Organization)
      url = Rails.application.routes.url_helpers.settings_org_billing_url(provider, host: GitHub.host_name)
    end

    {
      admin: !!provider&.admins&.exists?(@user.id),
      billingUrl: url,
      type: provider&.configurable_object&.class&.to_s,
    }
  end

  # Subclass of ::BillingPlatform::Client that builds the underlying Faraday
  # connection via GitHub::FaradayClient.internal so we get the standard
  # internal-service middleware stack (RequestID, TenantContext, Datadog,
  # Retries, Resilient) and the typhoeus adapter.
  class FaradayBackedBillingPlatformClient < ::BillingPlatform::Client
    private

    sig { params(blk: T.nilable(T.proc.params(conn: Faraday::Connection).void)).returns(Faraday::Connection) }
    def setup_default_connection(&blk)
      GitHub::FaradayClient.internal(BILLING_PLATFORM_SERVICE_NAME, url) do |conn|
        configure_connection(conn, &blk)
      end
    end
  end
  private_constant :FaradayBackedBillingPlatformClient

  sig { returns(::BillingPlatform::Client) }
  def billing_platform_client
    FaradayBackedBillingPlatformClient.new(
      host: GitHub.billing_platform_host,
      hmac_key: GitHub.billing_platform_hmac_secret_key,
    ) do |conn|
      conn.use GitHub::FaradayMiddleware::Datadog,
        stats: GitHub.dogstats,
        service_name: BILLING_PLATFORM_SERVICE_NAME,
        enable_path_tag: true

      # Override the default Retries middleware so CanProceedWithUsage (a
      # Twirp POST that isn't a Get*/List* RPC, and so doesn't match the
      # default RETRY_TWIRP_LAMBDA) is also retried. CPWU is a read-only
      # lookup and this controller already fails open on errors, so retrying
      # is safe.
      conn.use GitHub::FaradayMiddleware::Retries,
        **GitHub::FaradayClient::DEFAULT_RETRY_OPTIONS.merge(
          retry_if: lambda do |env, exception|
            GitHub::FaradayClient::RETRY_TWIRP_LAMBDA.call(env, exception) ||
              env.url.path.end_with?("/CustomerApi/CanProceedWithUsage")
          end,
        )
    end
  end
end
