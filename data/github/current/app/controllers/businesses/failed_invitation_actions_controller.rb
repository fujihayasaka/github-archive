# typed: true
# frozen_string_literal: true

class Businesses::FailedInvitationActionsController < Businesses::BusinessController
  before_action :business_admin_invitations_required
  before_action :manage_enterprise_invitations_required
  before_action :business_not_downgraded_to_free_plan_required

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
        render Businesses::People::FailedInvitationToolbarActionsComponent.new(
          business: this_business,
          selected_invitations: this_business.failed_invitations.where(id: params[:invitation_ids] || []), # make sure ids are in the failed_invitations collection
          failed_invitations: failed_invitations
        ), layout: false
      end
    end
  end
end
