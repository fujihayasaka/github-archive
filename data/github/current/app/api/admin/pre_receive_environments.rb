# typed: true
# frozen_string_literal: true

class Api::Admin::PreReceiveEnvironments < Api::Admin

  before do
    deliver_error!(404) unless GitHub.pre_receive_hooks_enabled?
  end

  # Get all environments
  # rubocop:todo GitHub/ControlAccess
  get "/admin/pre-receive-environments", operation_id: "enterprise-admin/list-pre-receive-environments" do
    scope = sort(PreReceiveEnvironment.scoped.includes(:hooks))
    environments = paginate_rel(scope)
    deliver :pre_receive_environment_hash, environments
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  get "/admin/pre-receive-environments/:pre_receive_environment_id", operation_id: "enterprise-admin/get-pre-receive-environment" do
    environment = find_pre_receive_environment!(param_name: :pre_receive_environment_id)
    deliver :pre_receive_environment_hash, environment
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  post "/admin/pre-receive-environments", operation_id: "enterprise-admin/create-pre-receive-environment" do
    data = receive_with_schema("pre-receive-environment", "create")
    accepted_attributes = attr(data, :name, :image_url)
    environment = PreReceiveEnvironment.new(accepted_attributes)
    environment.save
    deliver_error! 422, errors: environment.errors if environment.errors.present?
    deliver :pre_receive_environment_hash, environment, status: 201
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  patch "/admin/pre-receive-environments/:pre_receive_environment_id", operation_id: "enterprise-admin/update-pre-receive-environment" do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    update_pre_receive_environment
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  post "/admin/pre-receive-environments/:pre_receive_environment_id", operation_id: :deprecated do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    update_pre_receive_environment
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  get "/admin/pre-receive-environments/:pre_receive_environment_id/downloads/latest", operation_id: "enterprise-admin/get-download-status-for-pre-receive-environment" do
    environment = find_pre_receive_environment!(param_name: :pre_receive_environment_id)
    deliver :pre_receive_environment_download_hash, environment
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  post "/admin/pre-receive-environments/:pre_receive_environment_id/downloads", operation_id: "enterprise-admin/start-pre-receive-environment-download" do
    environment = find_pre_receive_environment!(param_name: :pre_receive_environment_id)
    environment.queue_download
    deliver_error! 422, errors: environment.errors if environment.errors.present?
    deliver :pre_receive_environment_download_hash, environment, status: 202
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  delete "/admin/pre-receive-environments/:pre_receive_environment_id", operation_id: "enterprise-admin/delete-pre-receive-environment" do
    environment = find_pre_receive_environment!(param_name: :pre_receive_environment_id)
    deliver_error! 422, errors: environment.errors unless environment.can_destroy? && environment.destroy
    deliver_empty status: 204
  end
  # rubocop:enable GitHub/ControlAccess

  private

  def update_pre_receive_environment
    data = receive_with_schema("pre-receive-environment", "update")
    accepted_attributes = attr(data, :image_url, :name)
    environment = find_pre_receive_environment!(param_name: :pre_receive_environment_id)
    environment.update(accepted_attributes)
    deliver_error! 422, errors: environment.errors if environment.errors.present?
    deliver :pre_receive_environment_hash, environment
  end

  def sort(scope)
    return scope unless params[:sort].present? || params[:direction].present?
    direction = params[:direction] || "asc"
    scope.sorted_by(params[:sort], direction)
  end
end
