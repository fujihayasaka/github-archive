# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    include Kernel

    # The max duration (in seconds) a request can take before it times out.
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
        end
      end || default_request_timeout
    end
  end
end
