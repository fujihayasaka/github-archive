# typed: strict
# frozen_string_literal: true

module GitHubModels
  extend GH::Domain::Registration

  DUAL_WRITE_FAILURE_METRIC = "github_models.mysql_dual_write_failure"

  register_domain GitHubModels::Domain
end
