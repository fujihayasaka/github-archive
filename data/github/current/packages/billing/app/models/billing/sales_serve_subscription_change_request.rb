# typed: strict
# frozen_string_literal: true

class Billing::SalesServeSubscriptionChangeRequest < ApplicationRecord::Domain::Billing
  has_many :items, foreign_key: "change_request_id", class_name: "Billing::SalesServeSubscriptionChangeRequestItem", inverse_of: :change_request, dependent: :destroy, validate: true
  accepts_nested_attributes_for :items
  belongs_to :customer

  validates_presence_of :request_uuid, :customer_id, :zuora_subscription_id
  validates :request_uuid, uniqueness: true

  attribute :request_uuid, :string, default: -> { SecureRandom.uuid }

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
end
