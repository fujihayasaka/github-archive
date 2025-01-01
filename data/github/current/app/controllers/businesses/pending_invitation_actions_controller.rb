# typed: true
# frozen_string_literal: true

class Businesses::PendingInvitationActionsController < Businesses::BusinessController
  before_action :business_admin_invitations_required
  before_action :business_owner_required

  depends_on_clusters ApplicationRecord::Mysql1,
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
    render Businesses::People::PendingInvitationToolbarActionsComponent.new(
      business: this_business,
      selected_invitations: selected_invitations,
      pending_invitations: pending_invitations,
      opts: { invitation_type: invitation_type }
    ), layout: false
  end

  private

  def invitation_type
    params[:invitation_type]
  end

  memoize def selected_invitations
    case invitation_type
    when "member"
      selected_member_invitations
    when "collaborator"
      selected_collaborator_invitations
    when "admin"
      selected_admin_invitations
    when "unaffiliated"
      selected_unaffiliated_invitations
    end
  end

  memoize def pending_invitations
    case invitation_type
    when "member"
      pending_member_invitations
    when "collaborator"
      pending_collaborator_invitations
    when "admin"
      pending_admin_invitations
    when "unaffiliated"
      pending_unaffiliated_invitations
    end
  end

  memoize def pending_member_invitations
    query_args = parse_query_string(query_param,
      filter_map: BusinessesHelper::PENDING_MEMBERS_QUERY_FILTERS,
    )
    sort_order = parse_sort_order(query_args)
    this_business
      .filtered_pending_invitations(
        query: query_args[:query],
        license: query_args[:license],
        organizations: query_args[:organizations],
        invitation_source: query_args[:source],
        order_by_direction: sort_order[:sort_direction],
        order_by_field: sort_order[:sort_field])
      .paginate(page: current_page)
  end

  memoize def selected_member_invitations
    if params[:invitation_ids]&.include?("all")
      this_business.pending_member_invitations.order(:email, :invitee_id).to_a
    else
      (params[:invitation_ids] || []).map do |id|
        # If a user has pending invites 41 and 42, the request will only send invite 41.
        # This finds all pending invites in an enterprise for a user given only one invite per user.
        first_invite_for_user = this_business.pending_invitations.find_by(id: id)
        next if first_invite_for_user.nil?
        all_invites = if first_invite_for_user.try(:invitee_id)
          this_business.pending_member_invitations.where(invitee_id: first_invite_for_user.invitee_id)
        else
          this_business.pending_member_invitations.where(email: first_invite_for_user.email)
        end
      end.flatten.compact
    end
  end

  memoize def pending_collaborator_invitations
    this_business.pending_collaborator_invitations.paginate(page: current_page)
  end

  memoize def selected_collaborator_invitations
    if params[:invitation_ids]&.include?("all")
      this_business.pending_collaborator_invitations
    else
      this_business.pending_collaborator_invitations.where(id: params[:invitation_ids] || [])
    end
  end

  memoize def pending_admin_invitations
    this_business.pending_admin_invitations.paginate(page: current_page)
  end

  memoize def selected_admin_invitations
    if params[:invitation_ids]&.include?("all")
      this_business.pending_admin_invitations
    else
      this_business.pending_admin_invitations.where(id: params[:invitation_ids] || [])
    end
  end

  memoize def pending_unaffiliated_invitations
    this_business.pending_unaffiliated_invitations.paginate(page: current_page)
  end

  memoize def selected_unaffiliated_invitations
    if params[:invitation_ids]&.include?("all")
      this_business.pending_unaffiliated_invitations
    else
      this_business.pending_unaffiliated_invitations.where(id: params[:invitation_ids] || [])
    end
  end
end
