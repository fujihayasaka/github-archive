# typed: strict
# frozen_string_literal: true

class Sponsors::Dashboard::Settings::DisconnectPatreonComponent < ApplicationComponent
  extend T::Sig

  # sponsorable - User or Organization disconnecting Patreon
  sig { params(sponsorable: GitHubSponsors::Types::Sponsorable).void }
  def initialize(sponsorable:)
    @sponsorable = sponsorable
  end

  private

  sig { returns(GitHubSponsors::Types::Sponsorable) }
  attr_reader :sponsorable

  sig { returns(T::Boolean) }
  def render?
    return false unless GitHub.sponsors_enabled? && sponsorable.sponsors_patreon_user.present?
    sponsorable.adminable_by?(current_user)
  end

  sig { returns(SponsorsPatreonUser) }
  memoize def sponsors_patreon_user
    T.must_because(sponsorable.sponsors_patreon_user) do
      "component does not render unless a SponsorsPatreonUser is present"
    end
  end

  sig { returns(String) }
  def patreon_email
    sponsors_patreon_user.patreon_email
  end
end
