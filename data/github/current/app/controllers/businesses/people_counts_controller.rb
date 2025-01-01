# typed: true
# frozen_string_literal: true

class Businesses::PeopleCountsController < Businesses::BusinessController
  include BusinessesHelper
  include ActionView::Helpers::NumberHelper

  before_action :login_required
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
    metric = case params[:metric]
    when "enterprise_org_members_count"
      enterprise_org_members_count
    when "enterprise_org_owners_count"
      enterprise_org_owners_count
    when "outside_collaborators_count"
      outside_collaborators_count(this_business)
    when "enterprise_owner_count"
      enterprise_owner_count
    when "enterprise_billing_manager_count"
      enterprise_billing_manager_count
    when "guest_collaborators_count"
      guest_collaborators_count
    when "unaffiliated_users_count"
      unaffiliated_users_count
    when "cloud_members_count"
      ghec_user_ids.count
    when "server_members_count"
      ghes_user_ids.count
    when "cloud_and_server_members_count"
      ghec_user_ids.intersection(ghes_user_ids).count
    end

    respond_to do |format|
      format.html do
        if metric
          render html: number_with_delimiter(metric)
        else
          render html: "", status: :not_found
        end
      end
    end
  end
end
