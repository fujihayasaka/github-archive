# frozen_string_literal: true

require "flipper"
require "flipper/adapters/active_record"

# This initializes our internal Flipper implementation which is managed
# via chatops, e.g.
#   .dependabot account features
#   .dependabot repo features
#   .dependabot rollout features
#
Flipper.configure do |config|
  config.default do
    adapter = Flipper::Adapters::ActiveRecord.new

    Flipper.new(adapter)
  end
end
