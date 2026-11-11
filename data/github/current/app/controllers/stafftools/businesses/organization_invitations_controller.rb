# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::OrganizationInvitationsController < Stafftools::Businesses::BusinessBaseController
  before_action :check_for_owners, only: %i(index)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: %i(index)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    render "stafftools/businesses/organization_invitation_list", locals: {
      invitation_status: status_from_param,
      invitations: this_business.organization_invitations.with_status(status_from_param).
        paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE),
    }
  end

  private

  memoize def status_from_param
    if %w(created accepted confirmed).include?(params[:status])
      params[:status].to_sym
    else
      :created
    end
  end
end
