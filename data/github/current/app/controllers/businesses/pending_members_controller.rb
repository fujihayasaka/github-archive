# typed: true
# frozen_string_literal: true

class Businesses::PendingMembersController < Businesses::BusinessController
  include BusinessesHelper
  include EnterpriseManagedUsersHelper

  before_action :business_admin_invitations_required
  before_action :non_idp_managed_business_required, only: %i(index)
  before_action :login_required
  before_action :read_enterprise_invitations_required
  before_action :user_required, only: %i(show)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Notify,
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
    query_args = parse_query_string(query_param, filter_map: BusinessesHelper::PENDING_MEMBERS_QUERY_FILTERS)
    sort_order = parse_sort_order(query_args)

    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "businesses/pending_members_list", locals: {
            business: this_business,
            query: query_param,
            pending_member_invitations: pending_member_invitations,
            order_by_field: sort_order[:sort_field],
            order_by_direction: sort_order[:sort_direction]
          }
        else
          render "businesses/pending_members", locals: {
            business: this_business,
            query: query_param,
            pending_member_invitations: pending_member_invitations,
            order_by_field: sort_order[:sort_field],
            order_by_direction: sort_order[:sort_direction]
          }
        end
      end
    end
  end

  def show
    # GitHub/DoNotAllowLogin is disabled because login is needed for SQL query
    invitations = this_business
      .pending_member_invitations(login: user.login) # rubocop:disable GitHub/DoNotAllowLogin
      .paginate(page: current_page)

    view = create_view_model(
      Businesses::InvitationsView,
      business: this_business,
      user: user
    )
    render "businesses/invitations/member", locals: {
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
end
