# typed: strict
# frozen_string_literal: true

class Sponsors::BulkSponsorshipFrequenciesController < ApplicationController
  extend T::Sig
  include Sponsors::SharedControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast,
    ApplicationRecord::Copilot,
  only: [:show]

  stylesheet_bundle :sponsors

  before_action :login_required_with_return_to_explore

  sig { void }
  def show
    render "sponsors/bulk_sponsorship_frequencies/show", locals: {
      sponsor: sponsor
    }
  end

  private

  sig { void }
  def login_required_with_return_to_explore
    redirect_to_login(sponsors_explore_index_path) unless logged_in?
  end

  sig { returns T.any(GitHubSponsors::Types::Sponsor, Symbol) }
  def target_for_conditional_access
    sponsor || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
