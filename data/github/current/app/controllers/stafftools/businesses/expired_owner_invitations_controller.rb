# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::ExpiredOwnerInvitationsController < Stafftools::Businesses::BusinessBaseController
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
    only: [:index],
    optional: true

  def index
    invitations = this_business.invitations.expired
      .with_business_role(:owner)
      .preload(:invitee)
      .order("business_member_invitations.created_at DESC")

    query = ActiveRecord::Base.sanitize_sql_like(params[:query].to_s.strip.downcase)
    if query.present?
      matching_invitee_ids = User
        .where("users.login LIKE :query OR users.display_name LIKE :query", query: "%#{query}%")
        .pluck(:id)
      invitations = invitations.where(invitee_id: matching_invitee_ids)
        .or(invitations.where("business_member_invitations.email LIKE :query", query: "%#{query}%"))
    end
    invitations = invitations.paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE)
    render "stafftools/businesses/expired_owner_invitations", locals: { expired_owner_invitations: invitations }
  end
end
