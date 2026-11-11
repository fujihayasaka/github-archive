# typed: strict
# frozen_string_literal: true

class Billing::SalesServeSubscriptionChangeRequest < ApplicationRecord::Domain::Billing
  include Instrumentation::Model

  has_many :items, foreign_key: "change_request_id", class_name: "Billing::SalesServeSubscriptionChangeRequestItem", inverse_of: :change_request, dependent: :destroy, validate: true
  accepts_nested_attributes_for :items
  belongs_to :customer
  belongs_to :actor, class_name: "User"

  validates_presence_of :request_uuid, :customer_id, :zuora_subscription_number, :actor_id
  validates :request_uuid, uniqueness: true

  attribute :request_uuid, :string, default: -> { SecureRandom.uuid }

  after_commit  :instrument_create, on: [:create]
  after_commit  :instrument_destroy, on: [:destroy]
  after_commit  :instrument_update, on: [:update]

  sig { returns(T::Boolean) }
  def pending?
    items.any?(&:status_pending?)
  end

  sig { returns(T::Boolean) }
  def github_advanced_security_change?
    items.any? { |item| item.product == Billing::SalesServeSubscriptionChangeRequestItem::PRODUCT_GITHUB_ADVANCED_SECURITY }
  end

  sig { returns(T::Boolean) }
  def github_enterprise_change?
    items.any? { |item| item.product == Billing::SalesServeSubscriptionChangeRequestItem::PRODUCT_GITHUB_ENTERPRISE }
  end

  sig { returns(T::Boolean) }
  def failed?
    items.any? { |item| item.status_error? || item.status_unknown? }
  end

  sig { returns(T::Boolean) }
  def success?
    items.all?(&:status_complete?)
  end

  sig { returns(T::Boolean) }
  def send_to_salesforce
    result = Hydro::PublishRetrier.publish(
      Hydro::EntitySerializer.sales_serve_subscription_change_request(self),
      schema: "github.billing.v0.SalesforceSubscriptionRequest",
      topic_format_options: {
        format_version: Hydro::Topic::FormatVersion::V2
      }
    )

    result.success?
  end

  private

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def item_payload
    items.map do |item|
      {
        product: item.product,
        product_rate_plan_charge_id: item.product_rate_plan_charge_id,
        type: item.change_type,
        status: item.status,
      }
    end
  end

  sig { void }
  def instrument_create
    instrument :create, change_items: item_payload
  end

  sig { void }
  def instrument_destroy
    instrument :destroy
  end

  sig { void }
  def instrument_update
    instrument :update, change_items: item_payload
  end

  sig { returns(String) }
  def event_prefix
    "sales_serve_subscription_change_request"
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def event_payload
    {
      business: customer&.business,
      actor: safe_actor,
    }
  end

  # Private: The user who performed the action. Check the GitHub request context for an actor override first.
  # If the context doesn't contain an actor, try the actor on the record. Otherwise, fallback to the ghost user.
  sig { returns(User) }
  def safe_actor
    User.find_by(id: GitHub.context[:actor_id]) || actor || User.ghost
  end
end
