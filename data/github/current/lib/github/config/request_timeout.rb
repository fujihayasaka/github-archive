# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    include Kernel

    # The max duration (in seconds) a request can take before it times out.
    #
    # IMPORTANT: This timeout applies only to the monolith worker processing time.
    #
    # There are multiple layers of timeouts in the request path:
    #   client -> GitHub edge site proxy -> GitHub datacenter proxy -> moda kube ingress -> nginx -> monolith worker
    #
    # Each connection in this chain has its own timeout settings:
    # - GLB (Global Load Balancer) has an idle connection timeout of ~11 seconds between proxy and monolith
    # - The monolith worker timeout (configured here) defines how long the worker can process before timing out
    #
    # Key implications:
    # - If a request takes longer than ~11 seconds with no traffic on the connection, GLB will terminate
    #   the connection and the client will see a timeout error (e.g., angry unicorn)
    # - HOWEVER, the monolith worker will continue processing the request until it completes or hits
    #   the worker timeout configured below
    # - This means the request may appear to fail from the client's perspective, but the backend
    #   processing continues and may succeed
    #
    # For endpoints with custom timeouts > 11 seconds:
    # - Consider if the long processing time is acceptable from a UX perspective
    # - For truly long-running operations (>10s), consider using async patterns:
    #   * Move the work to a background job
    #   * Implement client-side polling for status updates
    #   * Return immediately and notify the user when complete
    # - Keep the connection active with periodic status updates if synchronous processing is required
    #
    # See: https://thehub.github.com/epd/engineering/dev-practicals/containers/container-runtime/lifecycle-of-a-request/
    def request_timeout(env)
      env ||= {}
      request = Rack::Request.new(env)
      request_path = request.path_info

      # GitHub staff may adjust a request's timeout using ?timeout_override=<seconds>
      if request.GET.has_key?("timeout_override") && GitHub::StaffOnlyCookie.read(request.cookies)
        parsed = begin
          Float(request.GET["timeout_override"])
        rescue ArgumentError
          default_request_timeout
        end
        return parsed if parsed > 0
      end

      case request.request_method
      when "GET"
        case request_path
        when %r{\A/stafftools/users/([^/]+)(.*)/subpoena_discovery}
          [60, default_request_timeout].max
        when %r{\A/stafftools/audit_log}
          [60, default_request_timeout].max
        # The reused credit card fingerprints page can take longer to load depending on the number of accounts
        # sharing the same credit card fingerprint. There is ongoing work to improve the performance of this page.
        # https://github.com/github/billing-core/issues/1166
        when %r{\A/stafftools/reused_card_fingerprints}
          [60, default_request_timeout].max
        # The Devtool's surveys path needs a longer timeout because some surveys have a lot of users/answers on it and can't
        # be downloaded within the default timeout.
        # Context: https://github.com/github/feature-management/issues/838
        when %r{\A/devtools/surveys/([^/]+)(.*)}
          [120, default_request_timeout].max
        end
      else
        case request_path
        # The pull request merge API endpoint benefits from a longer timeout because the merge
        # orchestration performs multiple synchronous operations (rule evaluation, commit generation,
        # ref updates, etc.) that can exceed the default timeout for large repositories. When the
        # request times out mid-merge, it leaves the merge in an "in-progress" state, causing
        # subsequent retry attempts to receive HTTP 405 errors until a sweeper job cleans up the
        # stale state. A longer timeout allows the merge to complete and avoids this failure mode.
        #
        # Gated behind a feature flag so it can be targeted to specific repositories.
        #
        # See: https://github.com/github/git-systems/issues/5351
        when %r{\A/repositories/(\d+)/pulls/\d+/merge\z}
          repo_id = $1
          if FeatureFlag.vexi.enabled?(:merge_api_extended_timeout, "Repository:#{repo_id}", default: false)
            [30, default_request_timeout].max
          end
        # These are all request paths that take payment details like credit
        # card params and directly call Braintree APIs. They benefit from a
        # longer timeout. For more context see:
        #
        # https://github.com/github/github/pull/28356
        when %r{\A/account/billing/update_credit_card},
             %r{\A/account/cc_update},
             %r{\A/organizations/([^/]+)(.*)/billing/cc_update},
             %r{\A/organizations/([^/]+)(.*)/billing/update_credit_card},
             %r{\A/stafftools/users/([^/]+)(.*)/change_plan}
          [30, default_request_timeout].max
        when %r{\A/repositories\z},  # Create repo with upsell
             %r{\A/organizations\z}, # Create new paid organization
             %r{\A/join/plan\z},
             %r{\A/redeem/([^/]+)(.*)\z},
             %r{\A/site/custom_sleeptown\z}
          [20, default_request_timeout].max
        when %r{\A/_chatops/spokes}
          [120, default_request_timeout].max
        when %r{\A/_chatops/codespaces}
          [120, default_request_timeout].max
        when "/_commit_refs"
          [120, default_request_timeout].max
        # The Devtool's surveys path needs a longer timeout because some surveys have a lot of users/answers on it and can't
        # be downloaded within the default timeout.
        # Context: https://github.com/github/feature-management/issues/838
        when %r{\A/devtools/surveys/([^/]+)(.*)}
          [120, default_request_timeout].max
        # Requests to create an enterprise trial account need a longer timeout because synchronous requests are made
        # to the Proxima Tenant Metadata Service (TMS) when creating an enterprise with data residency.
        when %r{\A/account/enterprises/create},
             %r{\A/account/enterprises/check_subdomain}
          [30, default_request_timeout].max
        end
      end || default_request_timeout
    end
  end
end
