# typed: true
# frozen_string_literal: true

class Sponsors::Profile::MeetTheTeamsController < ApplicationController
  include Sponsors::AdminableControllerValidations

  before_action :organization_sponsorable_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  MEMBERS_LIMIT = 50

  def index
    render Sponsors::Dashboard::Profile::MeetTheTeamSearchResultsComponent.new(
      sponsorable: T.must(sponsorable),
      other_members: members_excluding_featured,
      query: query,
      current_featured_users: current_featured_users,
    ), layout: false
  end

  private

  sig { returns String }
  memoize def query
    params[:query].to_s.strip
  end

  sig { void }
  def organization_sponsorable_required
    return if sponsorable&.organization?
    render_404
  end

  sig { returns T::Array[User] }
  memoize def current_featured_users
    featured_users.map(&:featureable)
  end

  sig { returns T::Array[User] }
  memoize def members_excluding_featured
    sponsorable = T.must_because(self.sponsorable) { "#organization_sponsorable_required ensures non-nil" }
    members = T.cast(sponsorable, Organization).members.where.not(id: current_featured_users.map(&:id))
      .limit(MEMBERS_LIMIT)
    members = members.with_prefix("users.login", query.strip) if query.present?
    members.to_a
  end

  sig { returns T.any(GitHubSponsors::Types::Sponsorable, Symbol) }
  def target_for_conditional_access
    return :no_target_for_conditional_access unless sponsorable # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    T.must(sponsorable)
  end
end
