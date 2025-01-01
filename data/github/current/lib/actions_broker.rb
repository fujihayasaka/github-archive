# typed: true
# frozen_string_literal: true
# We used `ActionsBroker` instead of `Actions::Broker` to avoid interfering with the `Actions` module used by the packwerk package: https://github.com/github/github/tree/master/packages/actions
module ActionsBroker
  autoload :Twirp, "actions_broker/twirp"
end
