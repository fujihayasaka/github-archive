# typed: strict
# frozen_string_literal: true

# This ideally would be in the Copilot module
# Unfortunately, adding it there causes the "does not accidentally autoload at boot" test in
# test/integration/environment_test.rb to fail. This is because of the call to
# Rails.configuration.after_initialize in packages/copilot/initializers/copilot/subscribers.rb
# that causes the Copilot module to load on boot.
#
# If that ever gets fixed, this should be moved to the Copilot module.
module CopilotDomain
  extend GH::Domain::Registration

  register_domain Copilot::Domain
end
