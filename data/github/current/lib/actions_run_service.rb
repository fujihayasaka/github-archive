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
    # Lab URLs can be actions-run-lab.* (pod-specific format) or actions-run-service-lab.* (pod-agnostic format)
    host = run_stamp_uri.host
    host&.start_with?("actions-run-lab", "actions-run-service-lab")
  end

  # Selects the appropriate run-service Twirp client based on URL.
  # Prefers the URL if present (lab vs non-lab detection), otherwise falls back to
  # configured defaults. Returns nil if no usable configuration is available.
  def self.client_for_url(url:, use_lab: false)
    if url.present?
      is_lab = is_lab_url?(url)
      return Twirp::RunServiceLabClient.new(base_url: url) if is_lab

      return Twirp::RunServiceClient.new(base_url: url)
    end

    if use_lab
      return nil unless GitHub.actions_run_service_lab_address.present?

      return Twirp::RunServiceLabClient.new(base_url: GitHub.actions_run_service_lab_address)
    end

    return nil unless GitHub.actions_run_service_address.present?

    Twirp::RunServiceClient.new(base_url: GitHub.actions_run_service_address)
  rescue URI::InvalidURIError
    nil
  end
end
