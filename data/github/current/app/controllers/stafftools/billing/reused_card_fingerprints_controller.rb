# typed: true
# frozen_string_literal: true

class Stafftools::Billing::ReusedCardFingerprintsController < StafftoolsController
  depends_on_clusters(
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index, :lookup]
  )

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :lookup],
    optional: true

  sig { void }
  def index
    render(
      "stafftools/reused_card_fingerprints/index"
    )
  end

  sig { void }
  def lookup # rubocop:disable GitHub/UseRestfulActions
    card_fingerprint = T.must(params[:card_fingerprint])
    payment_methods = PaymentMethod.with_card_fingerprint(card_fingerprint).includes(:user, :manually_reviewed_by, customer: :business).order(created_at: :desc)
    blocklisted_payment_method = BlacklistedPaymentMethod.find_by_card_fingerprint(card_fingerprint) # rubocop:disable Naming/InclusiveLanguage

    raise ActiveRecord::RecordNotFound if payment_methods.none?

    render(
      "stafftools/reused_card_fingerprints/lookup",
      locals: {
        card_fingerprint: card_fingerprint,
        payment_methods: payment_methods,
        blocklisted_payment_method: blocklisted_payment_method,
        spamurai_link: Spam.url_for_account_login_ids(payment_methods.collect(&:user_id)),
      },
    )
  end

  sig { void }
  def update
    payment_method_action = T.must(params[:payment_method_action])
    card_fingerprint = T.must(params[:card_fingerprint])
    reason = params[:reason]
    undo_account_consequence = params[:undo_account_consequence].present? ? !!params[:undo_account_consequence] : false

    if reason.blank?
      flash[:error] = "A reason is mandatory to #{payment_method_action} this card fingerprint. Please provide a reason and try again."
    elsif payment_method_action == Stafftools::Billing::CardFingerprintDialogComponent::Action::Block.serialize
      consequence = T.must(params[:blocklist_consequence])
      payment_method = PaymentMethod.with_card_fingerprint(card_fingerprint).first
      deserialized_consequence = BlacklistedPaymentMethod::Consequence.deserialize(consequence)  # rubocop:disable Naming/InclusiveLanguage
      account = payment_method.owner
      blocklisted_payment_method = ::Billing::Public.blocklist_payment_method(account:, payment_method: payment_method, reason: reason, consequence:  deserialized_consequence, actor: current_user)

      if blocklisted_payment_method.present?
        consequence_action = nil
        if deserialized_consequence == BlacklistedPaymentMethod::Consequence::Suspended # rubocop:disable Naming/InclusiveLanguage
          consequence_action = "suspended"
        elsif deserialized_consequence == BlacklistedPaymentMethod::Consequence::BillingLocked # rubocop:disable Naming/InclusiveLanguage
          consequence_action = "locked billing for"
        end
        flash[:success] = "Succcessfully blocked payment fingerprint #{card_fingerprint} and #{consequence_action} all accounts associated to that fingerprint"
      else
        flash[:error] = "Something went wrong with blocklisting the payment method with card fingerprint #{card_fingerprint}. Please contact #billing-engineering on Slack."
      end
    elsif payment_method_action == Stafftools::Billing::CardFingerprintDialogComponent::Action::Unblock.serialize
      success = BlacklistedPaymentMethod.remove_payment_method(card_fingerprint: card_fingerprint, actor: current_user, reason: reason, undo_consequence: undo_account_consequence) # rubocop:disable Naming/InclusiveLanguage
      if success
        flash[:success] = "Succcessfully removed payment method with card fingerprint #{card_fingerprint} from the blocklist."
      else
        flash[:error] = "Something went wrong with removing the payment method with card fingerprint #{card_fingerprint} from the blocklist. Please try again."
      end
    else
      flash[:error] = "Unexpected action #{payment_method_action} for card fingerprint #{card_fingerprint}. Please contact #billing-engineering on Slack."
    end

    redirect_to lookup_stafftools_reused_card_fingerprints_path(card_fingerprint: card_fingerprint)
  end
end
