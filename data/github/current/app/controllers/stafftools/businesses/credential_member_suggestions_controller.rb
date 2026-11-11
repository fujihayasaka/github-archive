# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::CredentialMemberSuggestionsController < Stafftools::Businesses::BusinessBaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:index]

  def index
    return render_404 unless FeatureFlag.vexi.enabled?(:credential_revocation_single_user, current_user, default: false)

    headers["Cache-Control"] = "no-cache, no-store"
    search_query = params[:q].to_s.strip

    members = this_business
      .filtered_members(current_user, query: search_query.presence)
      .includes(:user)
      .paginate(page: 1, per_page: 10)

    users = members.filter_map(&:user)

    respond_to do |format|
      format.html_fragment do
        render partial: "stafftools/businesses/credential_member_suggestions",
          formats: [:html],
          locals: { users: users, query: search_query }
      end
      format.html do
        render partial: "stafftools/businesses/credential_member_suggestions",
          locals: { users: users, query: search_query }
      end
    end
  end
end
