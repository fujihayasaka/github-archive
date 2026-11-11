# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::UnaffiliatedMembersController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :dotcom_required, only: %i(index)
  before_action :check_for_owners, only: %i(index destroy)
  before_action :unaffiliated_member_required, only: :destroy

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: %i(index)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    render "stafftools/businesses/members/index", locals: {
      members: this_business
        .filtered_members(
          current_user,
          query: params[:query],
          role: "unaffiliated",
          ignore_org_membership_visibility: true,
          business_user_accounts_query: true,
          include_unaffiliated: true
        )
        .paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE),
      members_title: "Unaffiliated members",
      members_url: stafftools_enterprise_unaffiliated_members_path(this_business)
    }
  end

  def destroy
    BusinessOrchestration.remove_members(
      business: this_business,
      user_ids: [unaffiliated_member.id],
      actor: current_user,
      reason: "removing unaffiliated user",
      send_notification: true
    ).execute
    flash[:notice] = "Removing unaffiliated user #{unaffiliated_member}."
    redirect_to stafftools_enterprise_unaffiliated_members_path(this_business)
  end

  private

  def unaffiliated_member_required
    render_404 unless unaffiliated_member.present?
  end

  memoize def unaffiliated_member
    bua = this_business
      .user_accounts
      .exclusive_unaffiliated_role
      .find_by(user_id: params[:id])
    bua&.user
  end
end
