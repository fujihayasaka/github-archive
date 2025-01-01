# typed: strict
# frozen_string_literal: true

class Sponsors::Accounts::BreadcrumbsComponent < ApplicationComponent
  extend T::Sig

  sig { params(sponsorable: T.nilable(GitHubSponsors::Types::Sponsorable)).void }
  def initialize(sponsorable: nil)
    @sponsorable = sponsorable
  end

  sig { returns(T.nilable(GitHubSponsors::Types::Sponsorable)) }
  attr_reader :sponsorable
end
