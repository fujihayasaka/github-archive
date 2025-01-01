# typed: strict
# frozen_string_literal: true

class Sponsors::Profile::FeaturedSponsorshipsController < ApplicationController
  include Sponsors::AdminableControllerValidations

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
  only: [:index], optional: true

  sig { void }
  def index
    render Sponsors::Dashboard::Profile::FeaturedSponsorsSearchResultsComponent.new(
      sponsorable: T.must(sponsorable),
      other_sponsorships: sponsorships_excluding_featured,
      query: query,
      current_featured_sponsorships: current_featured_sponsorships,
    ), layout: false
  end

  private

  sig { returns String }
  memoize def query
    params[:query].to_s.strip
  end

  sig { returns T::Array[Sponsorship] }
  memoize def current_featured_sponsorships
    featured_sponsorships.map(&:featureable)
  end

  sig { returns T::Array[T.nilable(Integer)] }
  memoize def current_featured_sponsorships_ids
    current_featured_sponsorships.map(&:id)
  end

  sig { returns T::Array[Sponsorship] }
  memoize def sponsorships_excluding_featured
    sponsorable = T.must(self.sponsorable)

    featureable_sponsorships = Sponsorship.where(sponsorable_id: sponsorable.id).paid_or_patreon
    unless current_featured_sponsorships.empty?
      featureable_sponsorships = featureable_sponsorships.and(
        Sponsorship.where.not(id: current_featured_sponsorships_ids))
    end

    if query.present?
      user_ids = User.where(id: featureable_sponsorships.map(&:sponsor_id))
        .with_prefix("users.login", query.strip).pluck(:id)
      featureable_sponsorships = featureable_sponsorships.to_a.select { |sponsorship| user_ids.include?(sponsorship.sponsor_id) }
    end
    featureable_sponsorships.to_a
  end

  sig { returns T.any(GitHubSponsors::Types::Sponsorable, Symbol) }
  def target_for_conditional_access
    return :no_target_for_conditional_access unless sponsorable # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    T.must(sponsorable)
  end
end
