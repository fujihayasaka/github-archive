# typed: strict
# frozen_string_literal: true

class Billing::Zuora::SalesOperationsIssueDetails
  include GitHub::Memoizer
  include UrlHelpers

  sig { params(webhook: Billing::ZuoraWebhook).void }
  def initialize(webhook)
    @webhook = webhook
  end

  # Public: The relevant information needed to open a sales
  # operations issue for the sales serve webhooks
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def generate
    return {} unless webhook.is_sales_serve_kind?
    return {} if customer.nil?
    return {} if existing_account.nil?

    {
      new_issue_link: new_issue_link,
      title: title,
      description: description,
      ask: ask,
      links: links
    }
  end

  # Public: Return a prettified string version of the details
  sig { returns(String) }
  def to_s
    details = generate

    return "" if details.empty?

    buffer = StringIO.new
    buffer.puts "Link:"
    buffer.puts details[:new_issue_link]
    buffer.puts "\nTitle:"
    buffer.puts details[:title]
    buffer.puts "\nDescription:"
    buffer.puts details[:description]
    buffer.puts "\nAsk:"
    buffer.puts details[:ask]
    buffer.puts "\nLinks:"
    buffer.puts details[:links].compact.join(" - ")

    buffer.string
  end

  private

  sig { returns(Billing::ZuoraWebhook) }
  attr_reader :webhook

  sig { returns(String) }
  def new_issue_link
    "https://github.com/github/sales-operations/issues/new?labels=sales-support" \
    "%2C+Priority+-+To+Be+Triaged&template=25+-+Standard+Issue.md&title=Standard+Issue"
  end

  sig { returns(String) }
  def title
    "#{formatted_account(webhook_account)} #{webhook.kind} webhook unable to be processed due to re-used zuora account id"
  end

  sig { returns(String) }
  def description
    base = "We received a Zuora webhook targeting #{formatted_account(webhook_account)}. "
    if existing_account
      base += "It is already in use for the #{formatted_account(existing_account)}. "
    else
      base += "An existing customer is found with no associations. "
    end
    base + "Webhook ID for future @github/gitcoin first responder: #{webhook.id}"
  end

  sig { returns(String) }
  def ask
    "How should these accounts be associated to each other and/or Zuora?"
  end

  sig { returns(T::Array[String]) }
  def links
    [existing_account_zuora_link, account_stafftools_link(existing_account), account_stafftools_link(webhook_account)]
  end

  # Internal: The customer account tied to the subscription found in the webhook
  sig { returns(T.nilable(Customer)) }
  memoize def customer
    return unless subscription = self.subscription
    Customer.find_by(zuora_account_number: subscription[:accountNumber])
  end

  # Internal: The account associated with the found Customer record
  sig { returns(T.nilable(Billing::Types::OrgOrBusiness)) }
  memoize def existing_account
    return unless customer = self.customer

    customer.organizations.first || customer.business
  end

  # Internal: The Zuora subscription referenced in the webhook
  sig { returns(T.nilable(Zuorest::Model::Subscription)) }
  memoize def subscription
    Zuorest::Model::Subscription.find(webhook.subscription_id)
  end

  # Internal: The account linked to the webhook
  sig { returns(T.nilable(Billing::Types::OrgOrBusiness)) }
  memoize def webhook_account
    return unless subscription = self.subscription

    case
    when subscription[:DotcomEntAccountId__c].present?
      Business.find_by(id: subscription[:DotcomEntAccountId__c])
    when subscription[:DotcomOrgId__c].present?
      Organization.find_by(id: subscription[:DotcomOrgId__c])
    else
      nil
    end
  end

  # Internal: Identifier and type of account
  #
  # account - Organization or Business to format
  sig { params(account: T.nilable(Billing::Types::OrgOrBusiness)).returns(String) }
  def formatted_account(account)
    case account
    when Business
      "#{account.slug} (Enterprise Account)"
    when Organization
      "#{account.display_login} (Organization)"
    else
      ""
    end
  end

  # Internal: The Zuora link to the existing account
  sig { returns(String) }
  def existing_account_zuora_link
    return "Customer Not Found" unless customer = self.customer

    "[#{formatted_account(existing_account)} Zuora](#{GitHub.zuora_host}/apps/CustomerAccount.do?method=view&id=#{customer.zuora_account_id})"
  end

  # Internal: The stafftools link to the an account
  sig { params(account: T.nilable(Billing::Types::OrgOrBusiness)).returns(String) }
  def account_stafftools_link(account)
    return "" unless account

    url_options = { host: "admin.github.com", protocol: "https" }
    url = case account
    when Business
      stafftools_enterprise_url(account, **url_options)
    when Organization
      stafftools_user_url(account, **url_options)
    end
    "[#{formatted_account(account)} stafftools](#{url})"
  end
end
