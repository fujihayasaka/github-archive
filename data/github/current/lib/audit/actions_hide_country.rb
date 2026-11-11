# typed: true
# frozen_string_literal: true

# DO NOT EDIT
# THIS IS MAINTAINED AT https://github.com/github/audit-log-allowlists
# IF YOU NEED TO EDIT ANYTHING, please do so there.

module Audit
  module ActionsHideCountry
    ACTIONS = [
      "repo.self_hosted_runner_updated",
      "org.self_hosted_runner_updated",
      "enterprise.self_hosted_runner_updated",
    ]
  end
end
