# typed: strict
# frozen_string_literal: true

class PendingSubscriptionItemChangesController < ApplicationController
  include VerifiedFetchDependency

  before_action :login_required,
    :pending_change_required,
    :pending_subscription_item_change_adminable_by_current_user

  allow_verified_fetch only: [:destroy]

  sig { void }
  def update
    # ensures marketplace listing is not published
    listing = pending_subscription_item_change.listing
    if listing.is_a?(Marketplace::Listing) && !listing.draft?
      render_404 and return
    end

    pending_subscription_item_change.run
    pending_subscription_item_change.destroy

    flash[:notice] = "Pending change was successfully applied."
    redirect_back(fallback_location: "/")
  end

  sig { void }
  def destroy
    if pending_subscription_item_change.is_complete?
      error_message = "Cannot cancel a completed change."

      respond_to do |format|
        format.html do
          flash[:notice] = error_message
          return redirect_back(fallback_location: "/")
        end
        format.json { return render json: { error: error_message }, status: :unprocessable_entity }
      end
    end

    event = generate_hook_event(pending_subscription_item_change)
    delivery_system = Hook::DeliverySystem.new(event)
    delivery_system.generate_hookshot_payloads

    if pending_subscription_item_change.destroy
      delivery_system.deliver_later
      pending_subscription_item_change.instrument_undo_sponsorship_cancellation(actor: current_user)
    end

    success_message = "Successfully cancelled your pending change."
    respond_to do |format|
      format.html do
        flash[:notice] = success_message
        return redirect_back(fallback_location: "/")
      end
      format.json { return render json: { success: success_message } }
    end
  end

  private

  sig { returns(T.any(Symbol, ::Billing::Types::Account)) }
  def target_for_conditional_access
    # CAP is not needed if item is nil. We'd 404 unless user is logged in and can admin the item.
    return :no_target_for_conditional_access unless nilable_pending_subscription_item_change # rubocop:disable GitHub/SpecifyTargetForConditionalAccess

    billable_entity
  end

  sig { void }
  def pending_subscription_item_change_adminable_by_current_user
    return if current_user.site_admin? || pending_subscription_item_change.billable_entity.adminable_by?(current_user)

    render_404
  end

  sig { returns(T.nilable(Billing::PendingSubscriptionItemChange)) }
  memoize def nilable_pending_subscription_item_change
    Billing::PendingSubscriptionItemChange.find_by(id: params[:id])
  end

  sig { returns(Billing::PendingSubscriptionItemChange) }
  memoize def pending_subscription_item_change
    T.must(nilable_pending_subscription_item_change)
  end

  sig { void }
  def pending_change_required
    head :not_found unless nilable_pending_subscription_item_change
  end

  sig { params(change: Billing::PendingSubscriptionItemChange).returns(Hook::Event::MarketplacePurchaseEvent) }
  def generate_hook_event(change)
    Hook::Event::MarketplacePurchaseEvent.new({
      action: "pending_change_cancelled",
      sender_id: change.billable_entity.id,
      pending_subscription_item_change_id: change.id,
      subscription_item_id: T.must(change.subscription_item).id
    })
  end

  delegate :billable_entity, to: :pending_subscription_item_change, allow_nil: true
end
