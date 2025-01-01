# typed: true
# frozen_string_literal: true
require "turbomodel"

class Api::RepositoryCodeqlAutoModel < Api::App
  include Api::App::CodeScanningHelpers

  before do
    deliver_error! 404 if GitHub.enterprise? || GitHub.multi_tenant_enterprise?
  end

  # This is an experimental endpoint that is only meant to be used for a feasibility study
  # around using AI/LLMs for generating CodeQL threat models.
  #
  # More at https://github.com/github/code-scanning/issues/9495
  #
  # The endpoint is currently under /repositories because it was the easiest thing to implement
  # but it really doesn't have anything to do with the given repository currently (this might
  # change in the future).
  #
  # The endpoint is only accessible to staff members that have a specific feature flag enabled
  # (code_scanning_codeql_auto_model).
  post "/repositories/:repository_id/code-scanning/codeql/auto-model", operation_id: :internal do
    @route_owner = "@github/code-scanning-secexp"

    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }

    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)

    control_access :read_code_scanning,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_user_allowed_to_use_auto_model!

    data = receive(Hash)
    data.deep_symbolize_keys!

    # Manually create the request to ensure the data is in the correct format
    # This will decode fields according to the Protobuf JSON mapping
    # https://protobuf.dev/programming-guides/proto3/#json
    request = Turbomodel::Proto::AutoModelRequest.decode_json(data.to_json)
    response = GitHub::Turbomodel.auto_model(request)

    if response.error.present?
      status = Twirp::ERROR_CODES_TO_HTTP_STATUS[response.error.code]
      status = 500 if status.nil?
      # https://github.com/github/twirp-ruby/blob/0ba33116831c45ed8d865c9f00ef6b47174c2f57/lib/twirp/error.rb#L84-L92
      return deliver_raw(response.error.to_h, status: status)
    end

    deliver_raw response.data
  end

  private

  def ensure_user_allowed_to_use_auto_model!
    flag_enabled = GitHub.flipper[:code_scanning_codeql_auto_model].enabled?(current_user)
    is_staff = current_user.employee?

    return if flag_enabled && is_staff

    deliver_error!(403, message: "You are not authorized to use CodeQL auto-model")
  end
end
