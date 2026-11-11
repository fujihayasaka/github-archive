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

    if azure_subscription_id?(card_fingerprint)
      customers = Customer.with_azure_subscription_id(card_fingerprint)
        .includes(:business, customer_accounts: :user)
      raise ActiveRecord::RecordNotFound if customers.none?

      payment_method_wrappers = customers.map { |customer| PaymentMethodWrapper.from_customer_azure_subscription(customer) }.compact
      accounts = customers.filter_map(&:billable_owner).compact
      account_login_ids = accounts.collect(&:id)
    else
      payment_methods = PaymentMethod.with_card_fingerprint(card_fingerprint)
        .includes(:user, :manually_reviewed_by, customer: :business)
        .order(created_at: :desc)
      raise ActiveRecord::RecordNotFound if payment_methods.none?

      payment_method_wrappers = payment_methods.map { |pm| PaymentMethodWrapper.from_payment_method(pm) }
      account_login_ids = payment_methods.collect(&:user_id)
    end

    blocklisted_payment_method = BlacklistedPaymentMethod.find_by_card_fingerprint(card_fingerprint) # rubocop:disable Naming/InclusiveLanguage

    render(
      "stafftools/reused_card_fingerprints/lookup",
      locals: {
        card_fingerprint: card_fingerprint,
        payment_method_wrappers: payment_method_wrappers,
        blocklisted_payment_method: blocklisted_payment_method,
        spamurai_link: Spam.url_for_account_login_ids(account_login_ids)
      }
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
      payment_method_wrapper = payment_method_wrapper_for_fingerprint(card_fingerprint)
      deserialized_consequence = BlacklistedPaymentMethod::Consequence.deserialize(consequence)  # rubocop:disable Naming/InclusiveLanguage
      account = T.must(payment_method_wrapper.owner)
      blocklisted_payment_method = ::Billing::Public.blocklist_payment_method(
        account:,
        payment_method: payment_method_wrapper,
        reason: reason,
        consequence:  deserialized_consequence,
        actor: current_user
      )

      if blocklisted_payment_method.present?
        consequence_action = nil
        if deserialized_consequence == BlacklistedPaymentMethod::Consequence::Suspended # rubocop:disable Naming/InclusiveLanguage
          consequence_action = "suspended"
        elsif deserialized_consequence == BlacklistedPaymentMethod::Consequence::BillingLocked # rubocop:disable Naming/InclusiveLanguage
          consequence_action = "locked billing for"
        end
        flash[:success] = "Successfully blocked payment fingerprint #{card_fingerprint} and #{consequence_action} all accounts associated to that fingerprint"
      else
        flash[:error] = "Something went wrong with blocklisting the payment method with card fingerprint #{card_fingerprint}. Please contact #billing-engineering on Slack."
      end
    elsif payment_method_action == Stafftools::Billing::CardFingerprintDialogComponent::Action::Unblock.serialize
      success = BlacklistedPaymentMethod.remove_payment_method(card_fingerprint: card_fingerprint, actor: current_user, reason: reason, undo_consequence: undo_account_consequence) # rubocop:disable Naming/InclusiveLanguage
      if success
        flash[:success] = "Successfully removed payment method with card fingerprint #{card_fingerprint} from the blocklist."
      else
        flash[:error] = "Something went wrong with removing the payment method with card fingerprint #{card_fingerprint} from the blocklist. Please try again."
      end
    else
      flash[:error] = "Unexpected action #{payment_method_action} for card fingerprint #{card_fingerprint}. Please contact #billing-engineering on Slack."
    end

    redirect_to lookup_stafftools_reused_card_fingerprints_path(card_fingerprint: card_fingerprint)
  end

  private

  sig { params(identifier: String).returns(T::Boolean) }
  def azure_subscription_id?(identifier)
    identifier.match?(Customer::AZURE_SUBSCRIPTION_ID_FORMAT)
  end

  sig { params(fingerprint: String).returns(PaymentMethodWrapper) }
  def payment_method_wrapper_for_fingerprint(fingerprint)
    if azure_subscription_id?(fingerprint)
      PaymentMethodWrapper.from_azure_subscription_id(fingerprint)
    else
      payment_method = PaymentMethod.with_card_fingerprint(fingerprint).first
      PaymentMethodWrapper.from_payment_method(payment_method)
    end
  end
end
