# typed: true
# frozen_string_literal: true

class Api::Internal::Codespaces::Prebuilds < Api::Internal::Codespaces::Hmac
  INVALID_REF_MESSAGE = "Invalid ref. Ref must be a branch and must exist on the repository."

  post "/internal/vscs/codespaces/prebuild/instances", operation_id: :internal do
    @route_owner = "@github/codespaces"
    data = receive_with_schema("codespace", "codespaces-prebuild-instance", expected_type: Hash)
    repository_id, pool_code, vscs_target, vscs_target_url, location, environment_options, branch_name = data.values_at(
      "repository_id", "pool_code", "vscs_target", "vscs_target_url", "location", "environment_options", "branch_name")
    repository = find_repository(repository_id)
    validate_codespaces_prebuild_access!(repository, vscs_target, vscs_target_url)
    if vscs_target_url.present? && (vscs_target.to_s != "local")
      deliver_error!(400, message: "vscs_target must be 'local' to specify a devstamp URL")
    end
    authorize_vscs_target!(data["vscs_target"].to_sym)

    args = {
      repository: repository,
      pool_code: pool_code,
      location: location,
      vscs_target: vscs_target,
      vscs_target_url: vscs_target_url,
      branch: branch_name,
      entry_point: :rest_api_vscs_internal_prebuilds_post,
    }
    args[:environment_options] = environment_options if environment_options.present?
    ::Codespaces::CreatePrebuildInstanceJob.perform_later(**args)

    deliver_empty(status: 200)
  end

  # Used when template is deleted from vscs db
  delete "/internal/vscs/codespaces/prebuild/templates/:guid", operation_id: :internal do
    @route_owner = "@github/codespaces"

    data = receive_with_schema("codespace", "codespaces-prebuild-template-delete", expected_type: Hash)
    vscs_target = data["vscs_target"]

    if vscs_target.nil?
      vscs_target = ::Codespaces::Vscs.default_target
    end

    authorize_vscs_target!(vscs_target.to_sym)

    template = ::Codespaces::PrebuildTemplate.find_by(guid: params[:guid], vscs_target: vscs_target)
    unless template.nil?
      template.destroy!
    end

    deliver_empty(status: 204)
  end

  private

  def find_repository(repository_id)
    repository = Repository.find_by(id: repository_id)
    deliver_error!(404, message: "Not Found") unless repository&.owner&.codespaces_feature_enabled?
    repository
  end

  def validate_codespaces_prebuild_access!(repository, vscs_target, vscs_target_url)
    begin
      ::Codespaces::ValidatePrebuildAccess.call(repository: repository, vscs_target: vscs_target, vscs_target_url: vscs_target_url)
    rescue ::Codespaces::ValidatePrebuildAccess::AuthorizationError => e
      deliver_error! 403, message: e.message
    rescue ::Codespaces::ValidatePrebuildAccess::CreationCircuitBreaker => e
      deliver_error! 503, message: e.message
    end
  end
end
