# typed: true
# frozen_string_literal: true
# We used `ActionsBrokerWorker` instead of `Actions::BrokerWorker` to avoid interfering with the `Actions` module used by the packwerk package: https://github.com/github/github/tree/master/packages/actions
module ActionsBrokerWorker
  autoload :Twirp, "actions_broker_worker/twirp"
end
