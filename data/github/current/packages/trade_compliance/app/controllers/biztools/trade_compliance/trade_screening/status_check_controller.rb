# typed: strict
# frozen_string_literal: true

class Biztools::TradeCompliance::TradeScreening::StatusCheckController < BiztoolsController
  before_action :ensure_user_exists

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:show]

  sig { void }
  def show
    return render_404 unless request.xhr?

    render json: { screened: !couponable_entity.trade_screening_record.not_screened? }
  end

  private

  sig { returns(::Billing::Types::Account) }
  def couponable_entity
    current_account || current_business
  end
end
