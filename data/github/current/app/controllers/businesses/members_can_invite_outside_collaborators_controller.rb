# typed: true
# frozen_string_literal: true

class Businesses::MembersCanInviteOutsideCollaboratorsController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  def update
    return render_404 if this_business.enterprise_managed_user_enabled? && !this_business.emu_repository_collaborators_policy_enabled?

    setting_value = members_can_invite_outside_collaborators_params[:members_can_invite_outside_collaborators]
    message = ""

    validate_setting value: setting_value, valid_values: %w(no_policy repository_admins_allowed organization_admins_only enterprise_admins_only)

    case setting_value
    when "repository_admins_allowed"
      this_business.allow_members_can_invite_outside_collaborators(actor: current_user, force: true)
      message = "Repository admins can now #{helpers.invite_or_add_action_word.downcase} #{outside_collaborators_verbiage(this_business)}."
    when "organization_admins_only"
      this_business.disallow_members_can_invite_outside_collaborators(actor: current_user, force: true)
      message = "Repository admins will not be able to #{helpers.invite_or_add_action_word.downcase} #{outside_collaborators_verbiage(this_business)}."
    when "enterprise_admins_only"
      this_business.enterprise_admins_only_can_invite_outside_collaborators(actor: current_user)
      message = "Enterprise owners only can now #{helpers.invite_or_add_action_word.downcase} #{outside_collaborators_verbiage(this_business)}."
    when "no_policy"
      this_business.clear_members_can_invite_outside_collaborators(actor: current_user)
      message = "Organization administrators can now change this setting for individual organizations."
    end

    redirect_to :back, notice: message
  end

  private

  memoize def members_can_invite_outside_collaborators_params
    params.require(:business).permit(:members_can_invite_outside_collaborators)
  end
end
