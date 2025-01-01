# typed: true
# frozen_string_literal: true

class Businesses::SuspendedMembersController < Businesses::BusinessController
  before_action :login_required
  before_action :business_access_required
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :idp_managed_business_required

  skip_before_action :cap_pagination, only: :index

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

  def index
    query_args = parse_query_string(query_param)

    suspended_members = this_business
      .suspended_members(
        query: query_args[:query],
        viewer: current_user
      ).paginate(page: current_page)

    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "businesses/suspended_members_list", locals: {
            query: query_param,
            suspended_members: suspended_members,
          }
        else
          render "businesses/suspended_members", locals: {
            query: query_param,
            suspended_members: suspended_members,
          }
        end
      end
    end
  end

  private

  # The following actions do not need the EMU visibility policy.
  # We redirect anonymous requests to SSO in redirect_to_login as a UX improvement.
  def emu_visibility_enforceable
    return :no if %w(index).include?(action_name)
    :yes
  end
end
