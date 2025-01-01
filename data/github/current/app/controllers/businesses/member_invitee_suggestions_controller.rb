# typed: true
# frozen_string_literal: true

class Businesses::MemberInviteeSuggestionsController < Businesses::BusinessController
  before_action :business_supports_unaffiliated_user_accounts_required
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: %i(show)

  def show
    headers["Cache-Control"] = "no-cache, no-store"

    view = create_view_model(Businesses::MemberInvitations::InviteeSuggestionsView,
      exclude_suspended: true,
      prepend_friends: false,
      query: params[:q],
      business: this_business
    )

    respond_to do |format|
      format.html_fragment do
        render partial: "businesses/member_invitee_suggestions/suggestions", formats: :html, locals: { view: view }
      end
      format.html do
        render partial: "businesses/member_invitee_suggestions/suggestions", locals: { view: view }
      end
    end
  end

  private

  def business_supports_unaffiliated_user_accounts_required
    return render_404 unless this_business
    return render_404 if this_business.enterprise_managed_user_enabled?
    return render_404 unless this_business.supports_unaffiliated_user_accounts?
  end
end
