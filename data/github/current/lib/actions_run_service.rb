# typed: true
# frozen_string_literal: true
# We used `ActionsRunService` instead of `Actions::RunService` to avoid interfering with the `Actions` module used by the packwerk package: https://github.com/github/github/tree/master/packages/actions

require "actions-run-service"

module ActionsRunService
  autoload :Twirp, "actions_run_service/twirp"

  def self.is_lab_url?(run_stamp_url)
    run_stamp_uri = URI.parse(run_stamp_url)
    raise URI::InvalidURIError unless run_stamp_uri.kind_of?(URI::HTTP) || run_stamp_uri.kind_of?(URI::HTTPS)

    # https://github.com/github/actions-run-service/blob/main/config/kustomize/overlays/lab/kustomization.yml
    run_stamp_uri.host&.start_with?("actions-run-lab")
  end
end
