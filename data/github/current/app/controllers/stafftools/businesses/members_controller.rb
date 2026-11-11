# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::MembersController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :dotcom_required, only: :index
  before_action :check_for_owners
  before_action :member_required, only: :show

  depends_on_clusters \
    ApplicationRecord::Mysql1,
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

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    only: %i(show)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    render "stafftools/businesses/members/index", locals: {
      members: this_business
        .filtered_members(
          current_user,
          query: params[:query],
          ignore_org_membership_visibility: true
        )
        .paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE),
    }
  end

  def show
    render "stafftools/businesses/members/show"
  end

  private

  def member_required
    render_404 unless this_member.present?
  end

  memoize def this_member
    this_business.user_accounts.find_by(id: params[:id])
  end
  helper_method :this_member
end
