# typed: true
# frozen_string_literal: true

class Api::OrganizationPreReceiveHooks < Api::App
  include ReceiveSchemaWithOpenApi
  before do
    deliver_error!(404) unless GitHub.pre_receive_hooks_enabled?
  end

  get "/organizations/:organization_id/pre-receive-hooks", operation_id: "enterprise-admin/list-pre-receive-hooks-for-org" do
    control_access :list_org_pre_receive_hooks, resource: org = find_org!, allow_integrations: true, allow_user_via_granular_actor: true
    targets = PreReceiveHookTarget.visible_for_hookable(org).includes(:hook, :hookable)
    targets = paginate_rel(sort(targets))
    deliver :pre_receive_org_target_hash, targets
  end

  get "/organizations/:organization_id/pre-receive-hooks/:pre_receive_hook_id", operation_id: "enterprise-admin/get-pre-receive-hook-for-org" do
    control_access :read_org_pre_receive_hooks, resource: find_org!, allow_integrations: true, allow_user_via_granular_actor: true
    target = find_pre_receive_hook_target!(param_name: :pre_receive_hook_id)
    deliver :pre_receive_org_target_hash, target
  end

  patch "/organizations/:organization_id/pre-receive-hooks/:pre_receive_hook_id", operation_id: "enterprise-admin/update-pre-receive-hook-enforcement-for-org" do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    control_access :update_org_pre_receive_hooks,
      resource: org = find_org!,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    update_org_pre_receive_hook(org)
  end

  post "/organizations/:organization_id/pre-receive-hooks/:pre_receive_hook_id", operation_id: :deprecated do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    control_access :update_org_pre_receive_hooks,
      resource: org = find_org!,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    update_org_pre_receive_hook(org)
  end

  # Because this is presented to the user as deleting the overridden values, it returns the upstream target
  # after doing the delete.  Effectively as if a get was called.
  delete "/organizations/:organization_id/pre-receive-hooks/:pre_receive_hook_id", operation_id: "enterprise-admin/remove-pre-receive-hook-enforcement-for-org" do
    control_access :delete_org_pre_receive_hooks, resource: org = find_org!, allow_integrations: true, allow_user_via_granular_actor: true
    enforcement_target = find_pre_receive_hook_target!(param_name: :pre_receive_hook_id)
    # only delete if enforcement_target's hookable is the same org from the url
    unless enforcement_target.hookable == org
      deliver_error! 422, message: "There is no enforcement override to destroy"
    end
    enforcement_target.destroy
    target = find_pre_receive_hook_target!(param_name: :pre_receive_hook_id)
    deliver :pre_receive_org_target_hash, target
  end

  private

  def update_org_pre_receive_hook(org)
    data = receive_with_schema("pre-receive-hook", "update-for-org-legacy")
    accepted_attributes = attr(data, :enforcement, :allow_downstream_configuration)
    begin
      target = PreReceiveHookTarget.override_upstream_target(org, int_id_param!(key: :pre_receive_hook_id), accepted_attributes)
      deliver_error! 422, errors: target.errors if target.errors.present?
      deliver :pre_receive_org_target_hash, target, status: 200
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
