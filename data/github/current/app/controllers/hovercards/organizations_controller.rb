# typed: true
# frozen_string_literal: true

class Hovercards::OrganizationsController < ApplicationController
  before_action :require_xhr, only: :show

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Iam,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql5, optional: true, only: [:show]

  USE_SPAMMY_FILTER_LIMIT = 1000

  def show
    return render_404 if this_organization.spammy?

    # Calculate the members count
    user_ids = this_organization.visible_user_ids_for(current_user)
    if current_user&.feature_enabled?(:skip_filter_spammy_for_org_count_when_large) && user_ids.size > USE_SPAMMY_FILTER_LIMIT
      @member_count = user_ids.size
    else
      # Filter out spammy users, if size <= 1000. This balances reflecting which orgs are more trustworthy/popular
      # while avoiding slow queries.
      members = User.where(id: user_ids)
      @member_count = members.filter_spam_for(current_user).size
    end

    hydro_data = params.slice(:event_type, :click_target, :hover_target, :org, :subject, :payload).to_unsafe_h

    organization_enterprise = this_organization.business

    show_enterprise = with_database_error_fallback(fallback: false) do
      organization_enterprise&.readable_by?(current_user)
    end

    render "hovercards/organizations/show", locals: {
      organization: this_organization,
      member_count: @member_count,
      repository_count: repository_count,
      hydro_data: hydro_data,
      show_enterprise: show_enterprise
    }, layout: false
  end

  private

  memoize def this_organization
    Organization.find_by!(login: params[:org])
  end

  def target_for_conditional_access
    this_organization
  end

  def repository_count
    this_organization.visible_repositories_for(current_user, batched: true).size
  end
end
