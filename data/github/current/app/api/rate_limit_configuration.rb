# typed: true
# frozen_string_literal: true

# Public: A RateLimitConfiguration represents the rate limit rules for a
# specific API consumer and resource family. For example, for a given consumer
# (e.g., a specific user, a specific remote IP address, a specific OAuth app)
# accessing a given API resource family (e.g., the "search" family), a
# RateLimitConfiguration can tell you the rate limit rules (e.g., 20 requests
# per minute).
#
# If you want to know the *status* of a consumer's rate limit (i.e., how many
# requests they've used and when the rate limit resets), check out
# Api::RateLimitStatus and Api::Throttler.
class Api::RateLimitConfiguration
  # Historically, and by default, anonymous requests are limited by IP address. However certain rate
  # limiting families have different needs, and may want to add more nuance to how they group requests.
  #
  # If the @request_context includes Api::RateLimitConfiguration::AnonymousRequestKeyGenerator, then
  # the context's `anonymous_request_key_generator` method will be called to generate the key.
  # If it returns `nil`, the default behavior of using the remote IP address will be used.
  #
  # This gives endpoint owners the flexibility to roll out new strategies for rate limiting anonymous
  # requests in a way that can be measured, feature flagged, and tweaked, without affecting other API endpoint owners.
  #
  # Example use:
  #     class Api::Foo < Api::App
  #       include Api::RateLimitConfiguration::AnonymousRequestKeyGenerator
  #
  #       def anonymous_request_key_generator  # Abstract and required by including the module!
  #         "foo-#{request.env["HTTP_X_FOO"]}"
  #       end
  #     end
  module AnonymousRequestKeyGenerator
    extend T::Helpers

    abstract!

    sig { abstract.returns(T.nilable(String)) }
    def anonymous_request_key_generator; end
  end

  # Public: String name used to represent the family of resources governed by
  # the main API rate limit.
  DEFAULT_FAMILY = "core"

  # Public: String name used to represent the family of resources governed by
  # the Search API's rate limit.
  SEARCH_FAMILY = "search"

  # Public: String name used to represent the family of resources governed by
  # the Code Search API's rate limit.
  CODE_SEARCH_FAMILY = "code_search"

  # Special users with an higher rate limit
  CODE_SEARCH_EXPANDED_RATELIMIT_FAMILY = "code_search_expanded_ratelimit"

  # Public: String name used to represent the family of resources governed by
  # the Blackbird and Cardinal API's rate limits.
  BLACKBIRD_TIER1_FAMILY = "blackbird_tier1"
  BLACKBIRD_TIER2_FAMILY = "blackbird_tier2"

  # Public: String name used to represent the family of resources governed by
  # the Porter Import API's rate limit.
  #
  # NOTE: This rate limit family is no longer used in any API operations,
  # and will be dropped in the next API version. We're keeping it now to avoid
  # breaking changes in the `GET /rate_limit` API.
  SOURCE_IMPORT_FAMILY = "source_import"

  # Public: String name used to represent the GraphQL API endpoint.
  GRAPHQL_FAMILY = "graphql"

  # Public: String name used to represent the App manifest API
  INTEGRATION_MANIFEST_FAMILY = "integration_manifest"

  # Public: String name used to represent the Code Scanning upload API
  CODE_SCANNING_UPLOAD_FAMILY = "code_scanning_upload"

  # Public: String name used to represent the Actions Runner Registration API
  ACTIONS_RUNNER_REGISTRATION_FAMILY = "actions_runner_registration"

  # Public: String name used to represent SCIM API endpoints
  SCIM_FAMILY = "scim"

  # Public: String name used to represent the Dependency Snapshots API
  DEPENDENCY_SNAPSHOTS_FAMILY = "dependency_snapshots"

  # Public: String name used to represent the Audit Log API
  AUDIT_LOG_FAMILY = "audit_log"

  # Public: String name used to represent the Audit Log Streaming API
  AUDIT_LOG_STREAMING_FAMILY = "audit_log_streaming"

  # Private: String name used to represent the Git LFS API.
  LFS_FAMILY = "lfs"

  # Private: String name used to represent the Codespaces API
  CODESPACES_FAMILY = "codespaces"

  # Private: String name used to represent the Code Scanning variant analysis update API
  CODE_SCANNING_VARIANT_ANALYSIS_UPDATE_FAMILY = "code_scanning_variant_analysis_update"

  # Private: String name used to represent the Gist update API
  GIST_UPDATE_FAMILY = "gist_update"

  # Private: String name used to represent the family collaborator API
  OUTSIDE_COLLABORATORS_FAMILY = "collaborators"

  # This lists the families shown on the /rate_limit endpoint.
  # See Api::RateLimitStatus.
  PUBLIC_FAMILIES = [DEFAULT_FAMILY, SEARCH_FAMILY, GRAPHQL_FAMILY, INTEGRATION_MANIFEST_FAMILY, SOURCE_IMPORT_FAMILY, CODE_SCANNING_UPLOAD_FAMILY, ACTIONS_RUNNER_REGISTRATION_FAMILY, SCIM_FAMILY, DEPENDENCY_SNAPSHOTS_FAMILY, AUDIT_LOG_FAMILY, AUDIT_LOG_STREAMING_FAMILY, CODE_SEARCH_FAMILY].freeze

  # This lists the private families not shown on the /rate_limit endpoint.
  # See Api::RateLimitStatus.
  PRIVATE_FAMILIES = [LFS_FAMILY, CODESPACES_FAMILY, CODE_SCANNING_VARIANT_ANALYSIS_UPDATE_FAMILY, GIST_UPDATE_FAMILY, BLACKBIRD_TIER1_FAMILY, BLACKBIRD_TIER2_FAMILY, OUTSIDE_COLLABORATORS_FAMILY].freeze

  # The entire list of rate limit families
  ALL_FAMILIES = (PUBLIC_FAMILIES + PRIVATE_FAMILIES).freeze

  # Families for which we allow dynamic rate limits coming from apps and installations
  DYNAMIC_RATE_FAMILIES = [DEFAULT_FAMILY, GRAPHQL_FAMILY]

  # Internal: Hash of per-family rate limits for exempt users. On GHES these
  # users can be configured and on dotcom that should only be Hubot.
  #
  # IMPORTANT: If you need a higher rate limit for your API requests see this
  # article:
  #
  # https://github.com/github/githubber-content/blob/master/docs/technology/api-and-addons/increasing-api-rate-limits-for-hubbers.md
  EXEMPT_RATE_LIMITS = {
    DEFAULT_FAMILY => 120_000,
    SEARCH_FAMILY  => 500,
    ACTIONS_RUNNER_REGISTRATION_FAMILY => 40_000,
    OUTSIDE_COLLABORATORS_FAMILY => 120_000
  }.freeze

  # Public: Provide the rate limit configuration for a specific API consumer and
  # resource family.
  #
  # family          - The String name of the resource family.
  # request_context - An object that describes the request. Specifically, the
  #                   object must respond to #current_user, #current_app, and
  #                   #remote_ip. This information is used to identify the API
  #                   consumer.
  #
  # Returns an object that supports the public interface of an
  # Api::RateLimitConfiguration instance.
  def self.for(family, request_context)
    config_params = case family
    when DEFAULT_FAMILY
      {
        request_context: request_context,
        family: DEFAULT_FAMILY,
        unauthenticated_limit: GitHub.api_unauthenticated_rate_limit,
        authenticated_limit: GitHub.api_default_rate_limit,
        enterprise_cloud_soft_limit: GitHub.api_enterprise_cloud_soft_rate_limit,
        enterprise_cloud_hard_limit: GitHub.api_enterprise_cloud_hard_rate_limit,
        duration: 1.hour,
      }
    when SEARCH_FAMILY
      {
        request_context: request_context,
        family: SEARCH_FAMILY,
        unauthenticated_limit: GitHub.api_search_unauthenticated_rate_limit,
        authenticated_limit: GitHub.api_search_default_rate_limit,
        enterprise_cloud_hard_limit: GitHub.api_search_enterprise_cloud_hard_rate_limit,
        verified_limit: GitHub.api_search_default_rate_limit,
        duration: 1.minute,
      }
    when CODE_SEARCH_EXPANDED_RATELIMIT_FAMILY
      {
        request_context: request_context,
        family: CODE_SEARCH_EXPANDED_RATELIMIT_FAMILY,
        unauthenticated_limit: 0,
        authenticated_limit: 600,
        enterprise_cloud_hard_limit: 600,
        verified_limit: 600,
        duration: 1.minute,
      }
    when CODE_SEARCH_FAMILY
      {
        request_context: request_context,
        family: CODE_SEARCH_FAMILY,
        unauthenticated_limit: GitHub.api_code_search_unauthenticated_rate_limit,
        authenticated_limit: GitHub.api_code_search_default_rate_limit,
        enterprise_cloud_hard_limit: GitHub.api_code_search_enterprise_cloud_hard_rate_limit,
        verified_limit: GitHub.api_code_search_default_rate_limit,
        duration: 1.minute,
      }
    when BLACKBIRD_TIER1_FAMILY
      {
        request_context: request_context,
        family: family,
        unauthenticated_limit: 0,
        authenticated_limit: 120,
        enterprise_cloud_hard_limit: 120,
        verified_limit: 120,
        duration: 1.minute,
      }
    when BLACKBIRD_TIER2_FAMILY
      {
        request_context: request_context,
        family: family,
        unauthenticated_limit: 0,
        authenticated_limit: 600,
        enterprise_cloud_hard_limit: 600,
        verified_limit: 600,
        duration: 1.minute,
      }
    when SOURCE_IMPORT_FAMILY
      # NOTE: This rate limit family is no longer used in any API operations,
      # and will be dropped in the next API version. We're keeping it now to avoid
      # breaking changes in the `GET /rate_limit` API.
      {
        request_context: request_context,
        family: SOURCE_IMPORT_FAMILY,
        unauthenticated_limit: 5,
        authenticated_limit: 100,
        duration: 1.minute,
      }
    when AUDIT_LOG_FAMILY
      {
        request_context: request_context,
        family: AUDIT_LOG_FAMILY,
        unauthenticated_limit: GitHub.api_audit_log_unauthenticated_rate_limit,
        authenticated_limit: GitHub.api_audit_log_default_rate_limit,
        verified_limit: GitHub.api_audit_log_unauthenticated_rate_limit,
        duration: 1.hour,
      }
    when AUDIT_LOG_STREAMING_FAMILY
      {
        request_context: request_context,
        family: AUDIT_LOG_STREAMING_FAMILY,
        unauthenticated_limit: GitHub.api_audit_log_streaming_unauthenticated_rate_limit,
        authenticated_limit: GitHub.api_audit_log_streaming_default_rate_limit,
        verified_limit: GitHub.api_audit_log_streaming_unauthenticated_rate_limit,
        duration: 1.hour,
      }
    when GIST_UPDATE_FAMILY
      {
        request_context: request_context,
        family: GIST_UPDATE_FAMILY,
        unauthenticated_limit: GitHub.api_unauthenticated_rate_limit,
        authenticated_limit: 100,
        duration: 1.hour,
      }
    when LFS_FAMILY
      {
        request_context: request_context,
        family: LFS_FAMILY,
        unauthenticated_limit: GitHub.api_lfs_unauthenticated_rate_limit,
        authenticated_limit: GitHub.api_lfs_default_rate_limit,
        duration: 1.minute,
      }
    when INTEGRATION_MANIFEST_FAMILY
      {
        request_context: request_context,
        family: INTEGRATION_MANIFEST_FAMILY,
        unauthenticated_limit: GitHub.api_integration_manifest_unauthenticated_rate_limit,
        authenticated_limit: GitHub.api_default_rate_limit,
        duration: 1.hour,
      }
    when GRAPHQL_FAMILY
      user = T.let(request_context.try(:current_user), T.nilable(User))
      limit = if user && user.feature_enabled?(:graphql_higher_limit, memoize: false)
        if user.site_admin?
          GitHub.api_graphql_much_higher_rate_limit
        else
          GitHub.api_graphql_higher_rate_limit
        end
      else
        GitHub.api_graphql_default_rate_limit
      end
      {
        request_context: request_context,
        family: GRAPHQL_FAMILY,
        unauthenticated_limit: GitHub.api_graphql_unauthenticated_rate_limit,
        authenticated_limit: limit,
        enterprise_cloud_hard_limit: GitHub.api_graphql_enterprise_cloud_hard_rate_limit,
        duration: 1.hour,
      }
    when CODE_SCANNING_UPLOAD_FAMILY
      integration_installation = request_context.try(:current_integration_installation)
      authenticated_limit = GitHub.api_code_scanning_upload_rate_limit

      ActiveRecord::Base.connected_to(role: :reading) do
        # We constantize and create a new instance of the target type to avoid a database query to load the target.
        # Having its type and ID is all that we need here.
        target = T.let(integration_installation.nil? ? nil : integration_installation.target_type.constantize.new(id: integration_installation.target_id), T.nilable(GitHub::IFlipperActor))
        if target.nil? ? GitHub.flipper.feature(:code_scanning_higher_api_rate_limit).enabled? : GitHub.flipper[:code_scanning_higher_api_rate_limit].enabled?(target)
          authenticated_limit *= 4
        end
      end

      {
        request_context: request_context,
        family: CODE_SCANNING_UPLOAD_FAMILY,
        unauthenticated_limit: GitHub.api_unauthenticated_rate_limit,
        authenticated_limit: authenticated_limit.to_i,
        duration: 1.hour,
      }
    when CODE_SCANNING_VARIANT_ANALYSIS_UPDATE_FAMILY
      {
        request_context: request_context,
        family: CODE_SCANNING_VARIANT_ANALYSIS_UPDATE_FAMILY,
        unauthenticated_limit: GitHub.api_unauthenticated_rate_limit,
        authenticated_limit: GitHub.api_code_scanning_variant_analysis_update_rate_limit,
        duration: 1.hour,
      }
    when CODESPACES_FAMILY
      {
        request_context: request_context,
        family: CODESPACES_FAMILY,
        unauthenticated_limit: GitHub.api_unauthenticated_rate_limit,
        authenticated_limit: GitHub.api_codespaces_limit,
        duration: 1.hour,
      }
    when ACTIONS_RUNNER_REGISTRATION_FAMILY
      {
        request_context: request_context,
        family: ACTIONS_RUNNER_REGISTRATION_FAMILY,
        unauthenticated_limit: GitHub.api_unauthenticated_rate_limit,
        authenticated_limit: GitHub.api_actions_runner_registration_rate_limit,
        duration: 1.hour,
      }
    when SCIM_FAMILY
      {
        request_context: request_context,
        family: SCIM_FAMILY,
        unauthenticated_limit: GitHub.api_unauthenticated_rate_limit,
        authenticated_limit: GitHub.api_enterprise_cloud_hard_rate_limit,
        duration: 1.hour,
      }
    when DEPENDENCY_SNAPSHOTS_FAMILY
      {
        request_context: request_context,
        family: DEPENDENCY_SNAPSHOTS_FAMILY,
        unauthenticated_limit: GitHub.api_unauthenticated_rate_limit,
        authenticated_limit: GitHub.api_dependency_snapshots_rate_limit,
        duration: 1.minute,
      }
    when OUTSIDE_COLLABORATORS_FAMILY
      # we want to be able to limit Apps hitting that endpoint
      integration_installation = request_context.try(:current_integration_installation)
      hard_limit = GitHub.api_enterprise_cloud_hard_rate_limit
      soft_limit = GitHub.api_enterprise_cloud_soft_rate_limit

      ActiveRecord::Base.connected_to(role: :reading) do
        # We constantize and create a new instance of the target type to avoid a database query to load the target.
        # Having its type and ID is all that we need here.
        target = integration_installation.nil? ? nil : integration_installation.target_type.constantize.new(id: integration_installation.target_id)

        if (target && target&.feature_enabled?(:collaborator_api_rate_limit, memoize: false)) ||
          GitHub.flipper.feature(:collaborator_api_rate_limit).enabled?
          hard_limit, soft_limit = 5000
        end
      end

      {
        request_context: request_context,
        family: OUTSIDE_COLLABORATORS_FAMILY,
        unauthenticated_limit: GitHub.api_unauthenticated_rate_limit,
        authenticated_limit: GitHub.api_default_rate_limit, # the default for users is 5000
        enterprise_cloud_soft_limit: soft_limit,
        enterprise_cloud_hard_limit: hard_limit,
        duration: 1.hour,
      }
    else
      raise ArgumentError, "Unhandled RateLimitConfiguration family: #{family.inspect}. Add a case for it, or use one of the defined families."
    end

    new(**T.unsafe(config_params))
  end

  # @return [Boolean] true if this organization is on a high enough plan to qualify for an elevated rate limit
  def self.qualifies_for_higher_limit?(org)
    org.plan.business_plus?
  end

  attr_reader :family, :duration

  class << self
    # Use `.for(...)` to initialize RateLimitConfigurations, instead
    protected :new
  end

  # Initialize a RateLimitConfiguration.
  #
  # args - The Hash arguments used to initialize the instance:
  #        :family                - The String name of the resource family.
  #        :request_context       - An object that describes the request.
  #                                 Specifically, the object must respond to
  #                                 #current_user, #current_app, and #remote_ip.
  #        :unauthenticated_limit - The Integer maximum number of requests that
  #                                 an unauthenticated consumer can make for the
  #                                 resource family within the given rate limit
  #                                 duration.
  #        :authenticated_limit   - The Integer maximum number of requests that
  #                                 an authenticated consumer can make for the
  #                                 resource family within the given rate limit
  #                                 duration.
  #        :enterprise_cloud_soft_limit - If `request_context.request_owner` is an enterprise cloud customer,
  #                                       and this request is a dynamic rate limit family, this is the published limit.
  #                                       (In fact, they've got as much room as `enterprise_cloud_hard_limit`.)
  #        :enterprise_cloud_hard_limit - This is where we _actually_ cut off an enterprise cloud customer.
  #        :verified_limit        - The Integer maximum number of requests that
  #                                 an unauthenticated but verified consumer can
  #                                 make for the resource family within the
  #                                 given rate limit duration.
  #        :duration              - The Integer size of rate limit window in
  #                                 seconds.
  #
  # This constructor is not intended for use outside of this class. To obtain a
  # RateLimitConfiguration, use `RateLimitConfiguration.for`.
  def initialize(family:, request_context:, unauthenticated_limit:, authenticated_limit:, enterprise_cloud_soft_limit: nil, enterprise_cloud_hard_limit: nil, verified_limit: nil, duration:)
    @request_context       = request_context
    @user                  = request_context.current_user
    @authenticated_key     = request_context.authenticated_key
    @family                = family
    @unauthenticated_limit = unauthenticated_limit
    @authenticated_limit   = @user && @user.spammy? ? @unauthenticated_limit : authenticated_limit
    @enterprise_cloud_soft_limit = enterprise_cloud_soft_limit || authenticated_limit
    @enterprise_cloud_hard_limit = enterprise_cloud_hard_limit || @enterprise_cloud_soft_limit
    @verified_limit        = verified_limit || unauthenticated_limit
    @duration              = duration
    @app                   = request_context.current_app
    @integration_installation = request_context.current_integration_installation
    @request_owner = request_context.request_owner

    # not all request contexts passed will have a proxima_service_identity method defined. An example of this is
    # StaffTools::RateLimitContext, which is used for adjusting user rate limits in the staff tools.
    @proxima_service_identity = request_context.proxima_service_identity if request_context.respond_to?(:proxima_service_identity)

    # Figure out what kind of authentication and API access scenario we have,
    # and assign limits based on that.
    #
    # Each branch must assign `@limit` and `@runway`
    #
    # Wrap this in in `reading` because for `POST /graphql`, Api::Middleware::DatabaseSelection
    # doesn't apply, but we still want to send these queries to a replica.
    ActiveRecord::Base.connected_to(role: :reading) do
      if @user && @user.rate_limit_exempt_user? && EXEMPT_RATE_LIMITS.key?(family)
        @limit = EXEMPT_RATE_LIMITS[family]
        @runway = 0
      elsif DYNAMIC_RATE_FAMILIES.include?(family) && @integration_installation.present?
        @limit, @runway = ghec_limit_or(@integration_installation.rate_limit)
      elsif DYNAMIC_RATE_FAMILIES.include?(family) && @app.present?
        if @app.suspended?
          @limit = @unauthenticated_limit
          @runway = 0
        else
          @limit, @runway = ghec_limit_or(@app.rate_limit)
        end
      elsif authenticated_request?
        @limit, @runway = ghec_limit_or(@authenticated_limit)
      elsif @request_context.respond_to?(:rate_limit_verified?) && @request_context.rate_limit_verified?
        @limit = @verified_limit
        @runway = 0
      elsif GitHub.flipper[:proxima_service_rate_limits_primary].enabled? && @proxima_service_identity
        @limit = limit_for(proxima_service_identity: @proxima_service_identity)
        @runway = 0
        GitHub.dogstats.increment("api.proxima_service_identity", tags: ["limit:#{@limit}", "service_name:#{@proxima_service_identity.service_name}"])
      else
        @limit = @unauthenticated_limit
        @runway = 0
      end
    end
  end

  # @return [Integer] the max number of requests allowed for this config.
  attr_reader :limit

  # This is the number of tries which we allow _before_
  # decrementing the "remaining tries" number.
  #
  # For example, it's used for GHEC customers to grant them
  # a limit _higher_ than the documented limit, which we
  # can turn off with a feature flag.
  #
  # The size of the runway is the
  # difference between the hard limit and the soft limit:
  #
  # requests: ..............................xx
  #           |----------------------------|   hard limit
  #                                 |------|   soft limit
  #           |---------------------|          runway
  #                                         ^^ rate-limited
  #
  # @return [Integer]
  attr_reader :runway

  def key
    @key ||= if @user.present?
      RateLimitKey.for(@user)
    elsif @app.present?
      RateLimitKey.for(@app)
    elsif @authenticated_key.present?
      RateLimitKey.for(@authenticated_key)
    elsif GitHub.flipper[:proxima_service_rate_limits_primary].enabled? && @proxima_service_identity
      RateLimitKey.for(@proxima_service_identity)
    else
      anonymous_request_key
    end
  end

  def authenticated_request?
    if defined?(@authenticated_request)
      @authenticated_request
    else
      # don't credit suspended oauth apps with authenticated rate limits
      @authenticated_request = @user || (@app && !@app.suspended?) || @request_context.current_integration || @authenticated_key
    end
  end

  private

  def limit_for(proxima_service_identity:)
    # edge-case: handle case where the proxima service identity contains a rate_limit but a service_name that is not registered
    # this indicates a misconfigruation in the db and should be handled as an unauthenticated request
    return @unauthenticated_limit unless proxima_service_identity.present? && ProximaServiceIdentity::REGISTERED_SERVICES.include?(proxima_service_identity.service_name)
    return proxima_service_identity.rate_limit if proxima_service_identity.rate_limit.present?

    # if there isn't a rate_limit present, assume that a there is not a registered rate limit entry for the
    # tenant_shortcode/service_name combination and fall back to the default limit for the service. An exception
    # will be raised if the service isn't registered
    begin
      ProximaServiceIdentity.default_rate_limit(proxima_service_identity.service_name)
    rescue
      @unauthenticated_limit
    end
  end

  # If the GHEC limit applies to the `@request_owner` and
  # it's greater than `default_limit`, return it, along with the configured runway.
  # Otherwise, return the default limit and the default runway of `0`.
  # @param default_limit [Integer] returned if `@request_owner` doesn't qualify for the higher limit, or if `default_limit` is greater than the higher limit.
  # @param flag_enabled [Boolean] The flag check is done outside the method so that our linters recognize their usage
  # @return [Array(Integer, Integer)] The limit and runway
  def ghec_limit_or(default_limit)
    if @request_owner.present? && self.class.qualifies_for_higher_limit?(@request_owner)

      limit = if @enterprise_cloud_soft_limit > default_limit
        @enterprise_cloud_soft_limit
      else
        default_limit
      end

      # The hard limit is bigger than the soft limit, and that's where we actually cut people off.
      # The runway is the difference between the (big) hard limit and the (small) soft limit,
      # during that range, people's rate limit doesn't seem to go down --
      # not until they reach the "end" of the hard limit, then it decrements.

      hard_limit = @enterprise_cloud_hard_limit

      # In some cases, the previous limit is greater than the
      # new GHEC limit.
      # For example, some integration installations get 12,500 req/h,
      # but the new GraphQL hard limit is 10,000.
      runway = if hard_limit > limit
        hard_limit - limit
      else
        0
      end

      [
        limit,
        runway
      ]
    else
      [default_limit, 0]
    end
  end

  # Private: The rate limiting key to use for an anonymous request.
  # Default behavior (ip address-based keys) can be overridden by
  # request contexts that include the AnonymousRequestKeyGenerator module.
  # See also: Api::RateLimitConfiguration::AnonymousRequestKeyGenerator
  sig { returns(String) }
  def anonymous_request_key
    context_key = nil

    if @request_context.class.include?(AnonymousRequestKeyGenerator)
      context_key = @request_context.anonymous_request_key_generator
    end

    context_key || @request_context.env["HTTP_X_CLIENT_IP"] || @request_context.remote_ip
  end
end
