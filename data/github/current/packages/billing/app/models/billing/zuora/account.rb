# typed: strict
# frozen_string_literal: true

class Billing::Zuora::Account
  extend T::Sig

  # More info: https://developer.zuora.com/v1-api-reference/api/operation/POST_GenerateBillingDocuments/
  BILLING_DOCUMENTS_CHARGE_TYPE_TO_EXCLUDE = T.let({
    usage: "usage",
    recurring: "recurring",
    onetime: "onetime",
  }.freeze, T::Hash[Symbol, String])

  sig do
    params(zuora_account_id: T.nilable(String), attributes: UpdateAccountRequest)
      .returns(GitHub::Billing::Result)
  end
  def self.update(zuora_account_id, attributes)
    return GitHub::Billing::Result.success("not found") unless zuora_account_id.present?

    response = GitHub.zuorest_client.update_account(zuora_account_id, attributes.serialize)
    GitHub::Billing::Result.from_zuora(response)
  rescue Zuorest::HttpError => e
    Failbot.report!(e, app: "github-zuora")

    raise e
  end

  sig do
    params(zuora_account_id: T.nilable(String))
      .returns(T.nilable(Billing::Zuora::Account))
  end
  def self.find(zuora_account_id)
    return unless zuora_account_id.present?

    response = Zuorest::Model::Account.find(zuora_account_id)
    return unless response[:success]

    new(response)
  rescue Zuorest::HttpError => e
    Failbot.report!(e, app: "github-zuora")

    raise e
  end

  sig do
    params(zuora_account_number: T.nilable(String), zuora_subscription_id: T.nilable(String),
      charge_type_to_exclude: T.nilable(T::Array[T.nilable(String)]))
      .returns(T.nilable(GitHub::Billing::Result))
  end
  def self.generate_billing_documents(zuora_account_number, zuora_subscription_id, charge_type_to_exclude)
    return GitHub::Billing::Result.failure("zuora_account_number is not present") unless zuora_account_number.present?
    return GitHub::Billing::Result.failure("zuora_subscription_id is not present") unless zuora_subscription_id.present?

    attributes = {
      autoPost: true,
      effectiveDate: GitHub::Billing.today.to_s,
      subscriptionIds: [zuora_subscription_id],
      targetDate: GitHub::Billing.today.to_s,
      chargeTypeToExclude: charge_type_to_exclude,
    }

    response = GitHub.zuorest_client.generate_billing_documents(zuora_account_number, attributes)
    GitHub::Billing::Result.from_zuora(response)
  rescue Zuorest::HttpError => e
    Failbot.report!(e, app: "github-zuora")

    raise e
  end

  class BasicInfo < T::Struct
    const :id, String
    const :number, String, name: "accountNumber"
    # Possible values "Draft", "Active", "Canceled"
    # https://www.zuora.com/developer/api-reference/#operation/Object_GETAccount
    const :status, String

    const :apm_enabled, T.nilable(String), name: "APM__c"
    const :partner_customer, T.nilable(String), name: "PartnerCustomer__c"
  end

  class Metrics < T::Struct
    const :credit_balance, BigDecimal, name: "creditBalance", default: BigDecimal(0)
    const :balance, BigDecimal, default: BigDecimal(0)
  end

  class BillingAndPayment < T::Struct
    const :auto_pay, T::Boolean, name: "autoPay", default: false
    const :bill_cycle_day, Integer, name: "billCycleDay"
    const :currency, String, default: Billing::Money.default_currency
    const :default_payment_method_id, T.nilable(String), name: "defaultPaymentMethodId"
    const :payment_gateway, T.nilable(String), name: "paymentGateway"
  end

  class Contact < T::Struct
    const :id, T.nilable(String)
    const :first_name, T.nilable(String), name: "firstName"
    const :last_name, T.nilable(String), name: "lastName"
    const :work_email, T.nilable(String), name: "workEmail"
    const :address1, T.nilable(String)
    const :address2, T.nilable(String)
    const :city, T.nilable(String)
    const :state, T.nilable(String)
    const :zip_code, T.nilable(String), name: "zipCode"
    const :country, T.nilable(String)
  end

  class UpdateAccountRequest < T::Struct
    const :bill_to_contact, T.nilable(Contact), name: "billToContact"
    const :sold_to_contact, T.nilable(Contact), name: "soldToContact"
  end

  delegate :subscriptions, to: :zuorest_account
  delegate :id, :number, :status, to: :basic_info
  delegate :bill_cycle_day, :payment_gateway, to: :billing_and_payment
  delegate :work_email, to: :bill_to_contact

  sig { params(zuorest_account: Zuorest::Model::Account).void }
  def initialize(zuorest_account)
    @zuorest_account = zuorest_account
    @basic_info = T.let(BasicInfo.from_hash(zuorest_account[:basicInfo]), BasicInfo)
    @billing_and_payment = T.let(BillingAndPayment.from_hash(zuorest_account[:billingAndPayment]), BillingAndPayment)
    @metrics = T.let(Metrics.from_hash(zuorest_account[:metrics]), Metrics)
    @bill_to_contact = T.let(Contact.from_hash(zuorest_account[:billToContact]), Contact)
  end

  # Public: updates the Zuora external account with the given attributes
  # Note this does not update the local instance of the account
  sig do
    params(attributes: T::Hash[Symbol, T.untyped])
      .returns(T::Array[T::Hash[T.any(String, Symbol), T.untyped]])
  end
  def update!(attributes)
    zuorest_account.update!(attributes)
  end

  sig { returns(T::Boolean) }
  def active?
    "Active" == basic_info.status
  end

  sig { returns(T::Boolean) }
  def draft?
    "Draft" == basic_info.status
  end

  sig { returns(T::Boolean) }
  def canceled?
    "Canceled" == status
  end

  sig { returns(::Billing::Money) }
  def credit_balance
    credit_balance_dollars = metrics.credit_balance
    currency_code = billing_and_payment.currency

    Billing::Money.new(credit_balance_dollars * 100, currency_code)
  end

  sig { returns(::Billing::Money) }
  def balance
    Billing::Money.new(metrics.balance * 100, billing_and_payment.currency)
  end

  sig { returns(T::Boolean) }
  def auto_pay?
    billing_and_payment.auto_pay
  end

  # Public: Address of the contact whose billing information is used for the account
  #
  # Required keys include FirstName, LastName
  # Possible keys include Address1, Address2, City, State, PostalCode, and Country
  # https://www.zuora.com/developer/api-reference/#operation/Object_GETContact
  sig { returns(Sponsors::BillingContactResult) }
  def billing_contact
    # TODO: Replace this with the information from billToContact.
    # Check usages of BillingContactResult and see if we can get rid of that.
    return Sponsors::BillingContactResult.error("BillToId must be present") unless bill_to_contact.id.present?

    response = GitHub.zuorest_client.get_contact(bill_to_contact.id)

    Sponsors::BillingContactResult.success(response)
  rescue Zuorest::HttpError => e
    Failbot.report!(e, app: "github-zuora")
    return Sponsors::BillingContactResult.error(e.message) if e.status_code == 404

    raise e
  end

  # Public: Is this account included in the APM payment run?
  #
  # APM (Advanced Payment Manager) enablement is what allows us to collect payment for
  # sponsorships via a different gateway than other GitHub purchases.
  # See https://knowledgecenter.zuora.com/Zuora_Collect/Zuora_Collections/CA_Advanced_Payment_Manager
  sig { returns(T::Boolean) }
  def apm_enabled?
    basic_info.apm_enabled.to_s.downcase == "true"
  end

  sig { returns(T::Boolean) }
  def partner_customer?
    basic_info.partner_customer.to_s.downcase == "yes"
  end

  private

  sig { returns(BasicInfo) }
  attr_reader :basic_info

  sig { returns(Metrics) }
  attr_reader :metrics

  sig { returns(BillingAndPayment) }
  attr_reader :billing_and_payment

  sig { returns(Contact) }
  attr_reader :bill_to_contact

  sig { returns(Zuorest::Model::Account) }
  attr_reader :zuorest_account
end
