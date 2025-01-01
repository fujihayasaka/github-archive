# typed: strict
# frozen_string_literal: true

class Sponsors::AccountsController < ApplicationController
  extend T::Sig

  before_action :login_required
  before_action :check_trade_compliance

  layout "layouts/sponsors"

  stylesheet_bundle :sponsors

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  sig { void }
  def index
    # #sponsors_enabled_accounts preloads the SponsorsListing for each:
    sponsors_accounts = current_user.sponsors_enabled_accounts
    sponsorships_as_sponsor_count = current_user.sponsorships_as_sponsor.count

    render "sponsors/accounts/index", locals: {
      sponsors_accounts: sponsors_accounts,
      sponsorships_as_sponsor_count: sponsorships_as_sponsor_count,
    }
  end

  private

  sig { returns(T.any(User, Symbol)) }
  def target_for_conditional_access
    current_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
