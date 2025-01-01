# typed: true
# frozen_string_literal: true

class Api::Admin::PreReceiveHooks < Api::Admin
  include Repositories::Domain::Provider

  before do
    deliver_error!(404) unless GitHub.pre_receive_hooks_enabled?
  end

  # rubocop:todo GitHub/ControlAccess
  get "/admin/pre-receive-hooks", operation_id: "enterprise-admin/list-pre-receive-hooks" do
    scope = PreReceiveHookTarget.global.includes({ hook: [:environment, :repository, :targets] })
    targets = paginate_rel(sort(scope))
    deliver :pre_receive_hook_hash, targets
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  get "/admin/pre-receive-hooks/:pre_receive_hook_id", operation_id: "enterprise-admin/get-pre-receive-hook" do
    target = find_global_pre_receive_hook_target!(param_name: :pre_receive_hook_id)
    deliver :pre_receive_hook_hash, target
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  post "/admin/pre-receive-hooks", operation_id: "enterprise-admin/create-pre-receive-hook" do
    data = receive_with_schema("pre-receive-hook", "create")
    accepted_attributes = build_target_attributes(data)
    target = T.cast(PreReceiveHookTarget.create(accepted_attributes), PreReceiveHookTarget)
    deliver_error! 422, errors: target.errors if target.errors.present?
    deliver :pre_receive_hook_hash, target, status: 201
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  patch "/admin/pre-receive-hooks/:pre_receive_hook_id", operation_id: "enterprise-admin/update-pre-receive-hook" do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    update_pre_receive_hook
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  post "/admin/pre-receive-hooks/:pre_receive_hook_id", operation_id: :deprecated do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    update_pre_receive_hook
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  delete "/admin/pre-receive-hooks/:pre_receive_hook_id", operation_id: "enterprise-admin/delete-pre-receive-hook" do
    find_pre_receive_hook!(param_name: :pre_receive_hook_id).destroy
    deliver_empty status: 204
  end
  # rubocop:enable GitHub/ControlAccess

  private

  def update_pre_receive_hook
    data = receive_with_schema("pre-receive-hook", "update-for-ghe")
    target = find_global_pre_receive_hook_target!(param_name: :pre_receive_hook_id)
    accepted_attributes = build_target_attributes(data)
    target.update accepted_attributes
    deliver_error! 422, errors: target.errors if target.errors.present?
    deliver :pre_receive_hook_hash, target, status: 200
  end

  def build_target_attributes(data)
    data = { "enforcement" => "disabled",
            "allow_downstream_configuration" => false,
            "hookable" => GitHub.global_business }.merge(data)
    # If a script_repository is set, look it up by nwo and set the repository_id from that.
    if data["script_repository"].present?
      nwo = data["script_repository"]["full_name"]
      repository = repositories_domain.by_qualified_name(nwo)
      if repository
        data["repository_id"] = repository.id
      else
        deliver_error! 422, message: "Cannot use specified script_repository.",
                       errors: [api_error("PreReceiveHook", :script_repository, :invalid, value: nwo)]
      end
    end
    # Remap environment_id if environment is present in the received data
    data["environment_id"] = data["environment"]["id"] if data["environment"].present?
    data["hook_attributes"] = attr(data, :name, :script, :repository_id, :environment_id)
    attr(data, :enforcement, :allow_downstream_configuration, :hookable, :hook_attributes)
  end

  def sort(scope)
    scope.sorted_by("hook.#{params[:sort] || "id"}", params[:direction] || "asc")
  end
end
