# typed: true
# frozen_string_literal: true

class Businesses::PendingAdminsController < Businesses::BusinessController
  include BusinessesHelper

  before_action :business_admin_invitations_required
  before_action :non_scim_managed_business_required
  before_action :read_enterprise_invitations_required
  before_action :user_required, only: %i(show)

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
    query_args = parse_query_string(query_param,
      filter_map: BusinessesHelper::ADMINS_QUERY_FILTERS,
    )

    sort_order = parse_sort_order(query_args)
    pending_admins = this_business.pending_admin_invitations(
      query: query_args[:query],
      role: query_args[:role],
      order_by_direction: sort_order[:sort_direction],
      order_by_field: sort_order[:sort_field],
    ).paginate(page: current_page)

    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "businesses/admins/pending_list", locals: {
            query: query_param,
            pending_admins: pending_admins,
            order_by_direction: sort_order[:sort_direction],
            order_by_field: sort_order[:sort_field],
          }
        else
          render "businesses/admins/pending", locals: {
            query: query_param,
            pending_admins: pending_admins,
            order_by_direction: sort_order[:sort_direction],
            order_by_field: sort_order[:sort_field],
          }
        end
      end
    end
  end

  def show
    if GitHub.bypass_business_member_invites_enabled? && GitHub.site_admin_role_managed_externally?
      return render_404
    end

    # GitHub/DoNotAllowLogin is disabled because login is needed for SQL query
    invitations = this_business
      .pending_admin_invitations(login: user.login) # rubocop:disable GitHub/DoNotAllowLogin

    view = create_view_model(
      Businesses::InvitationsView,
      business: this_business,
      user: user
    )
    render "businesses/invitations/admin", locals: {
      invitations: invitations,
      member: user,
      view: view
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
