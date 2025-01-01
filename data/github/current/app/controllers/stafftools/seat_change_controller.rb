# typed: true
# frozen_string_literal: true

class Stafftools::SeatChangeController < StafftoolsController
  include SeatsHelper
  before_action :ensure_user_exists
  before_action :ensure_billing_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    only: [:show]

  def show
    seats = params[:seats] ? params[:seats].to_i : this_user.seats
    @seat_change = ::Billing::PlanChange::SeatChange.new(this_user, seats: seats)
    url = stafftools_user_seat_change_path(this_user, seats: seats, return_to: params[:return_to])

    publish_billing_seat_count_change_for(
      actor: current_user,
      user: this_user,
      old_seat_count: @seat_change.old_seats,
      new_seat_count: @seat_change.seats,
    )

    respond_to do |format|
      format.json do
        render json: hash_for_seat_change(seats, @seat_change, url)
      end
    end
  end

  private

  def publish_billing_seat_count_change_for(actor:,
                                       user:,
                                       new_seat_count: 0,
                                       old_seat_count: 0)
    GlobalInstrumenter.instrument(
      "billing.seat_count_change",
      actor_id: actor.id,
      user_id: user.id,
      old_seat_count: old_seat_count,
      new_seat_count: new_seat_count,
    )
  end
end
