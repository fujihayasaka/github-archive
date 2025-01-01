# typed: strict
# frozen_string_literal: true

class Sponsors::SignupStatusesController < ApplicationController
  extend T::Sig

  include Sponsors::AdminableControllerValidations

  before_action :require_xhr
  before_action :login_required
  before_action :non_banned_sponsors_listing_required
  before_action :require_acceptance_into_sponsors_program

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    only: [:show]

  sig { void }
  def show
    listing = T.must_because(sponsorable_sponsors_listing) { "required by non_banned_sponsors_listing_required" }

    render Sponsors::Dashboard::Overview::StatusComponent.new(
      sponsors_listing: listing
    ), layout: false
  end

  private

  sig { returns T.any(GitHubSponsors::Types::Sponsorable, Symbol) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
