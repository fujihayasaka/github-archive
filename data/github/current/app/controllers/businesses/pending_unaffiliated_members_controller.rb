# typed: true
# frozen_string_literal: true

class Businesses::PendingUnaffiliatedMembersController < Businesses::BusinessController
  include BusinessesHelper

  before_action :business_supports_unaffiliated_user_accounts_required
  before_action :business_admin_invitations_required
  before_action :non_scim_managed_business_required
  before_action :business_owner_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: %i(index)

  def index
    query_args = parse_query_string(query_param,
      filter_map: BusinessesHelper::UNAFFILIATED_QUERY_FILTERS,
    )

    sort_order = parse_sort_order(query_args)
    pending_members = this_business.pending_unaffiliated_invitations(
      query: query_args[:query],
      order_by_direction: sort_order[:sort_direction],
      order_by_field: sort_order[:sort_field],
    ).paginate(page: current_page)

    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "businesses/member_invitations/pending_list", locals: {
            query: query_param,
            pending_members: pending_members,
            order_by_direction: sort_order[:sort_direction],
            order_by_field: sort_order[:sort_field],
          }
        else
          render "businesses/member_invitations/pending", locals: {
            query: query_param,
            pending_members: pending_members,
            order_by_direction: sort_order[:sort_direction],
            order_by_field: sort_order[:sort_field],
          }
        end
      end
    end
  end

  def destroy
    invitation = this_business.invitations.pending.with_business_role(:unaffiliated).find_by!(id: params[:id])
    errors = []
    begin
      if invitation.cancelable_by?(current_user)
        invitation.cancel actor: current_user
      else
        errors << "#{current_user} cannot cancel unaffiliated member invitations for #{invitation.business.name}."
      end
    rescue BusinessAdministratorInvitation::AlreadyAcceptedError
      errors << "This invitation has already been accepted."
    end

    if errors.any?
      flash[:error] = errors.first
    else
      flash[:notice] = \
        "You've canceled #{invitation.email_or_invitee_name}'s invitation to become #{invitation.role_for_message} of #{invitation.business.name}."
    end
    redirect_to enterprise_pending_unaffiliated_members_path(this_business)
  end

  private

  def business_supports_unaffiliated_user_accounts_required
    return render_404 unless this_business
    return render_404 unless this_business.can_invite_unaffiliated_user_accounts?
  end
end
