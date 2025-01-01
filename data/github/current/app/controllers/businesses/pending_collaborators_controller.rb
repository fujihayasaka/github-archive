# typed: true
# frozen_string_literal: true

class Businesses::PendingCollaboratorsController < Businesses::BusinessController
  include BusinessesHelper
  include EnterpriseManagedUsersHelper

  before_action :business_admin_invitations_required
  before_action :non_idp_managed_business_required
  before_action :read_enterprise_invitations_required
  before_action :user_required, only: %i(show)
  before_action :business_not_downgraded_to_free_plan_required

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
    only: %i(index)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: %i(show)

  def index
    query_args = parse_query_string(query_param, filter_map: BusinessesHelper::OUTSIDE_COLLABORATORS_INVITATIONS_QUERY_FILTERS)
    sort_order = parse_sort_order(query_args)

    pending_collaborators = this_business.pending_collaborator_invitations(
      query: query_args[:query],
      order_by_field: sort_order[:sort_field],
      order_by_direction: sort_order[:sort_direction]
    ).paginate(page: current_page)

    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "businesses/pending_collaborators_list", locals: {
            query: query_param,
            pending_collaborators: pending_collaborators,
            order_by_field: sort_order[:sort_field],
            order_by_direction: sort_order[:sort_direction]
          }
        else
          render "businesses/pending_collaborators", locals: {
            query: query_param,
            pending_collaborators: pending_collaborators,
            order_by_field: sort_order[:sort_field],
            order_by_direction: sort_order[:sort_direction]
          }
        end
      end
    end
  end

  def show
    # GitHub/DoNotAllowLogin is disabled because login is needed for SQL query
    invitations = this_business.
      pending_collaborator_invitations(login: user.login). # rubocop:disable GitHub/DoNotAllowLogin
      paginate(page: current_page)

    render "businesses/invitations/outside_collaborator", locals: {
      invitations: invitations,
      member: user
    }
  end

  private

  memoize def login_param
    params[:login]
  end

  memoize def user
    User.find_by(login: login_param)
  end

  def user_required
    render_404 unless user
  end
end
