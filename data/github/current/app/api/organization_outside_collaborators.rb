# typed: true
# frozen_string_literal: true

class Api::OrganizationOutsideCollaborators < Api::App
  include ReceiveSchemaWithOpenApi

  # list outside collaborators in org
  get "/organizations/:organization_id/outside_collaborators", operation_id: "orgs/list-outside-collaborators" do
    org = find_org!

    set_forbidden_message "You must be an owner of this organization to list outside collaborators."
    control_access :list_outside_collaborators,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    users = org.outside_collaborators
    users = users.two_factor_disabled if filters.include?("2fa_disabled")
    users = users.with_insecure_two_factor_methods if filters.include?("2fa_insecure") && org.feature_flag_enabled?(:org_members_2fa_level, default: false)

    deliver :user_hash, paginate_rel(users.order(:login))
  end

  put "/organizations/:organization_id/outside_collaborators/:username", operation_id: "orgs/convert-member-to-outside-collaborator" do
    org  = find_org!
    user = record_or_404(this_user)
    # Introducing strict validation of the organization-membership.convert-to-outside-collaborator
    # JSON schema would cause breaking changes for integrators
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("organization-membership", "convert-to-outside-collaborator", skip_validation: true) || {}
    async = (data["async"] == true) || (data["async"] == "true")

    control_access :manage_org_users,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    unless org.allow_conversion_to_outside_collaborator?(actor: current_user)
      deliver_error! 403, message: "Converting members to outside collaborators is restricted to enterprise owners."
    end

    if org.member?(user)
      begin
        org.prevent_removal_of_last_admin!(user, "You can't demote the last admin")
      rescue Organization::NoAdminsError
        deliver_error! 403, message: "Cannot convert the last owner to an outside collaborator"
      else
        if async
          # This queues a background job to convert the user to an outside collaborator
          org.convert_to_outside_collaborator(user)
          deliver_empty(status: 202)
        else
          org.convert_to_outside_collaborator!(user)
          deliver_empty(status: 204)
        end
      end
    else
      deliver_error! 404, message: "#{user.login_for_api} is not a member of the #{org.login_for_api} organization."
    end
  end

  # remove an outside collaborator
  delete "/organizations/:organization_id/outside_collaborators/:username", operation_id: "orgs/remove-outside-collaborator" do
    # Introducing strict validation of the organization-collaborator.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("organization-collaborator", "delete", skip_validation: true)

    org = find_org!
    outside_collaborator = this_user

    set_forbidden_message "You must be an owner of this organization to remove outside collaborators."
    control_access :remove_outside_collaborator,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if org.member?(outside_collaborator)
      # The model method will protect against this case, but we explicitly check
      # here so we can deliver a better error message.
      deliver_error! 422, message: "You cannot specify an organization member to remove as an outside collaborator."
    else
      if org.user_is_outside_collaborator?(outside_collaborator.id)
        org.remove_outside_collaborator(outside_collaborator)
      end
      deliver_empty(status: 204)
    end
  end

  private

  def filters
    params[:filter].try(:split, ",") || []
  end
end
