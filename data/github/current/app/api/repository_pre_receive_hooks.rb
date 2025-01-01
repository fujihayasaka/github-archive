# typed: true
# frozen_string_literal: true

class Api::RepositoryPreReceiveHooks < Api::App
  include ReceiveSchemaWithOpenApi

  before do
    deliver_error!(404) unless GitHub.pre_receive_hooks_enabled?
  end

  get "/repositories/:repository_id/pre-receive-hooks", operation_id: "enterprise-admin/list-pre-receive-hooks-for-repo" do
    control_access :list_repo_pre_receive_hooks,
      repo: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    targets = PreReceiveHookTarget.visible_for_hookable(repo).includes(:hook, :hookable)
    targets = paginate_rel(sort(targets))
    deliver :pre_receive_repo_target_hash, targets
  end

  get "/repositories/:repository_id/pre-receive-hooks/:pre_receive_hook_id", operation_id: "enterprise-admin/get-pre-receive-hook-for-repo" do
    control_access :read_repo_pre_receive_hooks,
      repo: find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    target = find_pre_receive_hook_target!(param_name: :pre_receive_hook_id)
    deliver :pre_receive_repo_target_hash, target
  end

  patch "/repositories/:repository_id/pre-receive-hooks/:pre_receive_hook_id", operation_id: "repos/update-pre-receive-hook" do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    control_access :update_repo_pre_receive_hooks,
      repo: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    update_repo_pre_receive_hook(repo)
  end

  post "/repositories/:repository_id/pre-receive-hooks/:pre_receive_hook_id", operation_id: :deprecated do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    control_access :update_repo_pre_receive_hooks,
      repo: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    update_repo_pre_receive_hook(repo)
  end

  delete "/repositories/:repository_id/pre-receive-hooks/:pre_receive_hook_id", operation_id: "enterprise-admin/remove-pre-receive-hook-enforcement-for-repo" do
    control_access :delete_repo_pre_receive_hooks,
      repo: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    enforcement_target = find_pre_receive_hook_target!(param_name: :pre_receive_hook_id)
    # only delete if enforcement_target's hookable is the same org from the url
    unless enforcement_target.hookable == repo
      deliver_error! 422, message: "There is no enforcement override to destroy"
    end
    enforcement_target.destroy
    target = find_pre_receive_hook_target!(param_name: :pre_receive_hook_id)
    deliver :pre_receive_repo_target_hash, target
  end

  private

  def update_repo_pre_receive_hook(repo)
    data = receive_with_schema("pre-receive-hook", "update-for-repo-legacy")
    accepted_attributes = attr(data, :enforcement)
    begin
      target = PreReceiveHookTarget.override_upstream_target(repo, int_id_param!(key: :pre_receive_hook_id), accepted_attributes)
      deliver_error! 422, errors: target.errors if target.errors.present?
      deliver :pre_receive_repo_target_hash, target, status: 200
    rescue PreReceiveHookTarget::NotAllowedByUpstreamError
      deliver_error! 422, message: "Overriding settings is disallowed by an upstream configuration"
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      deliver_error! 409, message: "Conflicting updates for this record"
    end
  end

  def sort(scope)
    scope.sorted_by("hook.#{params[:sort] || "id"}", params[:direction] || "asc")
  end
end
