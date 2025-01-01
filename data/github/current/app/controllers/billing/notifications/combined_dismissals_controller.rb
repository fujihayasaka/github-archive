# typed: true
# frozen_string_literal: true

class Billing::Notifications::CombinedDismissalsController < Billing::Notifications::DismissalsController
  def create
    create_dismissal_per_item

    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end

  private

  def create_dismissal_per_item
    params[:dismissal_items].each do |dismissal_item|
      notice_key = dismissal_item[:notice_key]
      product_tag = dismissal_item[:product_tag]

      Billing::Notifications::Dismissal
        .new(account: account, actor_id: current_user.id)
        .create(notice_key, product_tag: product_tag)
    end
  end
end
