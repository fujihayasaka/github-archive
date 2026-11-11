# frozen_string_literal: true

module ChatopThrottler
  extend ActiveSupport::Concern

  FIDO_PROTECTED_ACTIONS = %i(throttler_set throttler_lock throttler_unlock).freeze

  # rubocop:disable Metrics/BlockLength
  included do
    before_action :require_fido_2fa, only: FIDO_PROTECTED_ACTIONS

    chatop :throttler_status,
           /throttler[-_]status/,
           "throttler-status "\
           "- Show the current Pull Request throttler configuration" do
      rate_limit = Throttlers.pull_request.rate_limit

      status = "PR creation limited to #{rate_limit.limit} "\
               "requests per #{rate_limit.frequency} seconds"

      if rate_limit.locked?
        status += "\nPR creation rate limit is currently locked: " +
                  rate_limit.lock_reason
      end

      jsonrpc_success status
    end

    chatop :throttler_set,
           /throttler[-_]set\s+(?<l>\d+)\s+per\s+(?<f>\d+)\s+sec(ond)?s?/,
           "throttler-set <limit> per <frequency> seconds "\
           "- Set the Pull Request throttler to <limit> requests "\
           "per <frequency> seconds" do
      limit = jsonrpc_params[:l].to_i
      frequency = jsonrpc_params[:f].to_i
      if limit.zero? || frequency.zero?
        jsonrpc_failure "Invalid rate limit of #{limit} requests "\
                        "per #{frequency} seconds"
        return
      end

      rate_limit = Throttlers.pull_request.rate_limit

      if rate_limit.locked?
        jsonrpc_failure "PR creation rate limit is currently locked: " +
                        rate_limit.lock_reason
      else
        rate_limit.set_limit(limit, frequency)
        jsonrpc_success "PR creation rate limit updated to "\
                        "#{rate_limit.limit} requests per "\
                        "#{rate_limit.frequency} seconds"
      end
    end

    chatop :throttler_lock,
           /throttler[-_]lock\s+(?<reason>.+)/,
           "throttler-lock <reason>"\
           "- Lock the Pull Request throttler against further changes" do
      rate_limit = Throttlers.pull_request.rate_limit

      if rate_limit.locked?
        jsonrpc_success "PR creation rate limit already locked: " +
                        rate_limit.lock_reason
      else
        rate_limit.lock(reason: jsonrpc_params[:reason])
        jsonrpc_success("I have locked the PR creation rate limit")
      end
    end

    chatop :throttler_unlock,
           /throttler[-_]unlock/,
           "throttler-unlock "\
           "- Unlock the Pull Request throttler rate limit "\
           "allowing changes" do
      Throttlers.pull_request.rate_limit.unlock!

      jsonrpc_success("I have unlocked the PR creation rate limit")
    end
  end
  # rubocop:enable Metrics/BlockLength
end
