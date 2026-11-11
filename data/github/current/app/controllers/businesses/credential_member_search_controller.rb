# typed: true
# frozen_string_literal: true

class Businesses::CredentialMemberSearchController < Businesses::BusinessController
  before_action :write_enterprise_credentials_required
  before_action :not_ghes_required
  before_action :single_user_revocation_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:show]

  def show
    headers["Cache-Control"] = "no-cache, no-store"
    search_query = params[:q].to_s.strip

    members = this_business
      .filtered_members(current_user, query: search_query.presence)
      .includes(:user)
      .paginate(page: 1, per_page: 10)

    users = members.filter_map(&:user)

    # The first EMU owner cannot be targeted for revocation, so exclude them from the picker.
    first_emu_owner = this_business.find_first_emu_owner
    users = users.reject { |user| user.id == first_emu_owner.id } if first_emu_owner

    respond_to do |format|
      format.html_fragment do
        render partial: "businesses/credential_member_search/results",
          formats: [:html],
          locals: { users: users }
      end
      format.html do
        render partial: "businesses/credential_member_search/results",
          locals: { users: users }
      end
    end
  end

  private

  def single_user_revocation_required
    render_404 unless FeatureFlag.vexi.enabled?(:credential_revocation_single_user, this_business, default: false)
  end

  def not_ghes_required
    render_404 if GitHub.single_tenant_enterprise?
  end
end
