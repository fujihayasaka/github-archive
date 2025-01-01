# typed: strict
# frozen_string_literal: true

class Sponsors::Dashboard::Settings::ConnectPatreonComponent < ApplicationComponent
  extend T::Sig

  # sponsorable - User or Organization connecting to Patreon
  sig { params(sponsorable: GitHubSponsors::Types::Sponsorable).void }
  def initialize(sponsorable:)
    @sponsorable = sponsorable
  end

  private

  sig { returns(GitHubSponsors::Types::Sponsorable) }
  attr_reader :sponsorable

  sig { returns(T::Boolean) }
  def render?
    return false unless GitHub.sponsors_enabled?
    return false if sponsorable.sponsors_patreon_user.present?

    sponsorable.adminable_by?(current_user)
  end
end
