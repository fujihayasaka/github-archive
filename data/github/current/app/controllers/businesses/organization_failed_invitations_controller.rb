# typed: true
# frozen_string_literal: true

class Businesses::OrganizationFailedInvitationsController < Businesses::BusinessController
  include ActionView::Helpers::TextHelper

  before_action :business_admin_invitations_required
  before_action :business_owner_required
  skip_before_action :cap_pagination, only: %i(show)

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: %i(show)

  def show
    query_args = parse_query_string(query_param, filter_map: BusinessesHelper::FAILED_INVITATIONS_QUERY_FILTERS)
    sort_order = parse_sort_order(query_args)
    failed_invitations = this_business.filtered_failed_invitations(
      query: query_args[:query],
      order_by_field: sort_order[:sort_field],
      order_by_direction: sort_order[:sort_direction]
    )
    .paginate(page: current_page)

    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "businesses/failed_invitations_list", locals: {
            business: this_business,
            query: query_param,
            failed_invitations: failed_invitations,
            order_by_field: sort_order[:sort_field],
            order_by_direction: sort_order[:sort_direction]
          }
        else
          render "businesses/failed_invitations", locals: {
            business: this_business,
            query: query_param,
            failed_invitations: failed_invitations,
            order_by_field: sort_order[:sort_field],
            order_by_direction: sort_order[:sort_direction]
          }
        end
      end
    end
  end

  def update
    invitations = get_failed_invitations_for(params[:invitation_ids])

    if invitations.blank?
      flash[:error] = "No invitations found matching the selected invitations"
      return redirect_to enterprise_failed_invitations_path(this_business)
    end

    invites_by_org = invites_by_org(invitations)
    errors = []

    org_ids = invites_by_org.keys
    org_ids.each do |org_id|
      email_or_invitee_logins = []
      invitation_ids = []

      invites_by_org[org_id].each do |invitation|
        begin
          invitation.cancel actor: current_user, notify: false
        rescue OrganizationInvitation::AlreadyAcceptedError
          errors << "Selected invitation to join the enterprise has already been accepted."
        end
        invitation.instrument_retry_invite(actor: current_user)
        email_or_invitee_logins << invitation.email_or_invitee_login
        invitation_ids << invitation.id
      end

      OrganizationBulkInviteJob.perform_later \
        current_user,
        Organization.find(org_id),
        email_or_invitee_logins,
        invitation_ids
    end

    if errors.any?
      # If one of the invites couldn't be revoked, but others succeded, we probably need to give more info than just an error
      flash[:error] = errors.first
    else
      flash[:notice] = "You've retried #{pluralize(invitations.length, 'invitation')} from the enterprise. It may take a few minutes for the retry to process."
    end
    redirect_to enterprise_failed_invitations_path(this_business)
  end

  def destroy
    invitations = get_failed_invitations_for(params[:invitation_ids])

    if invitations.blank?
      flash[:error] = "No invitations found matching the selected invitations"
      return redirect_to enterprise_failed_invitations_path(this_business)
    end

    errors = []

    invitations.each do |invitation|
      begin
        invitation.cancel actor: current_user
      rescue OrganizationInvitation::AlreadyAcceptedError
        errors << "Selected invitation to join the enterprise has already been accepted."
      end
    end

    if errors.any?
      # If one of the invites couldn't be revoked, but others succeded, we probably need to give more info than just an error
      flash[:error] = errors.first
    else
      flash[:notice] = "You've canceled #{pluralize(invitations.length, 'invitation')} from #{this_business.name}."
    end
    redirect_to enterprise_failed_invitations_path(this_business)
  end

  private

  def invites_by_org(invitations)
    invites_by_org = {}
    invitations.each do |invitation|
      invites_by_org[invitation.organization_id] ||= []
      invites_by_org[invitation.organization_id] << invitation
    end

    invites_by_org
  end

  def get_failed_invitations_for(invitation_ids)
    this_business.failed_invitations.select { |invite| invitation_ids.include?(invite.id.to_s) }
  end
end
