# typed: true
# frozen_string_literal: true

class Businesses::PeopleCountsController < Businesses::BusinessController
  include BusinessesHelper
  include ActionView::Helpers::NumberHelper
  include ActionView::Helpers::UrlHelper

  before_action :login_required
  before_action :read_enterprise_members_required

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
    metric_data = case params[:metric]
    when "enterprise_org_members_count"
      { count: enterprise_org_members_count, label: "Organization members", role: "member" }
    when "enterprise_org_owners_count"
      { count: enterprise_org_owners_count, label: "Organization owners", role: "owner" }
    when "outside_collaborators_count"
      { count: outside_collaborators_count(this_business), label: outside_collaborators_verbiage(this_business), outside_collaborators: true }
    when "enterprise_owner_count"
      { count: enterprise_owner_count, label: "Enterprise owners", role: "enterprise_owner" }
    when "enterprise_billing_manager_count"
      { count: enterprise_billing_manager_count, label: "Billing managers", role: "billing_manager" }
    when "guest_collaborators_count"
      { count: guest_collaborators_count, label: "Guest collaborators", role: "guest_collaborator" }
    when "unaffiliated_users_count"
      { count: unaffiliated_users_count, label: "Unaffiliated", role: "unaffiliated" }
    when "cloud_members_count"
      { count: ghec_user_ids.count, label: "Cloud members" }
    when "server_members_count"
      { count: ghes_user_ids.count, label: "Server members" }
    when "cloud_and_server_members_count"
      { count: ghec_user_ids.intersection(ghes_user_ids).count, label: "Cloud and server members" }
    end

    respond_to do |format|
      format.html do
        if metric_data
          formatted_count = number_with_delimiter(metric_data[:count])

          if metric_data[:outside_collaborators]
            href = enterprise_outside_collaborators_path(this_business)
          elsif metric_data[:role]
            href = people_enterprise_path(this_business.slug, query: "role:#{metric_data[:role]}")
          end

          if href
            render html: link_to(formatted_count, href,
              "aria-label": "#{metric_data[:label]}: #{formatted_count}",
              class: "Link--secondary")
          else
            render html: formatted_count
          end
        else
          render html: "", status: :not_found
        end
      end
    end
  end
end
