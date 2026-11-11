# typed: strict
# frozen_string_literal: true

class Sponsors::PatreonSponsorshipNoticeComponent < ApplicationComponent
  sig { params(user_or_org: GitHubSponsors::Types::Sponsor).void }
  def initialize(user_or_org:)
    @user_or_org = user_or_org
  end

  private

  sig { returns(GitHubSponsors::Types::Sponsor) }
  attr_reader :user_or_org

  sig { returns(T::Boolean) }
  def render?
    return false unless GitHub.sponsors_enabled? && user_or_org.present?
    return false unless user_or_org.sponsors_patreon_user.present?

    Sponsorship.from_sponsor(user_or_org).active.patreon.any?
  end

  sig { returns(String) }
  def sponsoring_path
    return user_path(user_or_org, params: { tab: :sponsoring }) if user_or_org.user?

    org_sponsoring_path(user_or_org)
  end
end
