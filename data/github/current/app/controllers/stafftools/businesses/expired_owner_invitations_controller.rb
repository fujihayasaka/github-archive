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
      .left_joins(:invitee)
      .order("business_member_invitations.created_at DESC")

    query = ActiveRecord::Base.sanitize_sql_like(params[:query].to_s.strip.downcase)
    if query.present?
      invitations = invitations.left_joins(invitee: :profile)
        .where([
          "users.login LIKE :query OR profiles.name LIKE :query OR business_member_invitations.email LIKE :query",
          { query: "%#{query}%" }
        ])
        .references(:users, :profile)
    end
    invitations = invitations.paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE)
    render "stafftools/businesses/expired_owner_invitations", locals: { expired_owner_invitations: invitations }
  end
end
