# typed: strict
# frozen_string_literal: true

class EnterpriseTeamMemberSuggestionsController < Businesses::BusinessController
  extend T::Sig

  before_action :business_access_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:index]

  sig { void }
  def index
    query_args = parse_query_string(query_param)
    query = query_args[:query]
    if query.blank?
      members = []
    else
      members = this_business.filtered_members(
        current_user,
        query: query,
        business_user_accounts_query: this_business.supports_unaffiliated_user_accounts?,
        include_unaffiliated: true,
        deployment: "cloud"
      ).limit(10)
    end

    headers["Cache-Control"] = "no-cache, no-store"

    respond_to do |format|
      format.json do
        render json: {
          enterprise_members: members.filter_map do |member|
            {
              id: GitHub.enterprise? ? member.id : member.user.id,
              login: member.display_login,
              name: member.name
            } if GitHub.enterprise? ? member.user? : member.user
          end
        }
      end
    end
  end
end
