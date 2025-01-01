# typed: true
# frozen_string_literal: true

class Codespaces::Billing::VNextMessageHandlerBase < Codespaces::Command
  include GitHub::Memoizer
  include Codespaces::UniqueCodespaceBillingIdentifierHelper

  class UnimplementedError < StandardError; end

  attr_reader :billing_message, :tracked_usage, :billing_entry

  def initialize(billing_message:, tracked_usage:, billing_entry:)
    @billing_message = billing_message
    @tracked_usage = tracked_usage
    @billing_entry = billing_entry
  end

  def perform
    return unless should_publish?

    result = if billing_message.is_prod_vscs_target?
      GitHub.dogstats.increment("codespaces.billing_usage.dispatched.count", tags: ["class:#{self.class.name&.underscore}"])
      publish_usage(transform_usage)
    elsif GitHub.flipper[:codespaces_billing_test_non_prod].enabled?
      publish_non_prod_usage(transform_usage)
      nil
    end

    post_perform
    result
  end

  private

  # can be overwritten by child classes
  def post_perform
  end

  def billing_billable_owner
    billing_entry.billable_owner&.billable_owner
  end

  # non-vscs_target specific checks go here
  memoize def should_publish?
    return false unless pre_should_publish?

    # Use the billable_owner method on the org/user to handle delegating to businesses or other special cases
    return false if billing_billable_owner.nil?
    return false if billing_billable_owner.free_codespace_use_enabled?
    return false if billing_entry.billable_owner.free_codespace_use_enabled? && billing_entry.billable_owner&.feature_enabled?(:codespaces_billable_owner_free_direct_check)
    return false unless billing_entry.for_codespace? || billing_entry.for_prebuild?
    true
  end

  # can be overwritten by child classes
  def pre_should_publish?
    true
  end

  def quantity
    raise UnimplementedError
  end

  memoize def transform_usage
    {
      sku: billing_sku,
      quantity: quantity,
      usage_at: Google::Protobuf::Timestamp.new(seconds: billing_message.period_end.to_i, nanos: 0),
      source_uri: billing_message.source_uri,
      entity: {
        customer_id: billing_entry.billable_owner&.billing_customer&.id,
        organization_id: billing_entry.repository&.organization_id,
        repo_id: billing_entry.repository_id,
        actor_id: actor_id,
      },
      usage_uuid: GitHub::Billing::MeteredProduct.usage_uuid(unique_billing_identifier)
    }
  end

  def billing_sku
    raise UnimplementedError
  end

  def actor_id
    raise UnimplementedError
  end

  def unique_billing_identifier
    raise UnimplementedError
  end

  def publish_usage(usage)
    Codespaces::BillingMessageHandlerResult.new(hydro_topic: "billingplatform.v1.Usage", hydro_payload: usage, publisher: Codespaces::BillingMessageHandlerResult::PUBLISH_RETRIER)
  end

  def transform_usage_for_splunk(usage)
    usage_to_semconv_field_map = {
      "sku": "gh.codespaces.billing_message.product_sku_name",
      "quantity": "gh.codespaces.billing_message.quantity",
      "seconds": "gh.codespaces.billing_message.usage_at.seconds",
      "nanos": "gh.codespaces.billing_message.usage_at.nanos",
      "source_uri": "gh.codespaces.billing_message.source_uri",
      "customer_id": "gh.billing.customer.id",
      "organization_id": "gh.org.id",
      "repo_id": "gh.repo.id",
      "actor_id": "gh.user.id",
      "usage_uuid": "gh.codespaces.billing_message.usage_uuid",
    }

    flattened_usage = usage.each_with_object({}) do |(key, value), result|
      if value.is_a? Hash
        result.merge!(value)
      elsif value.is_a? Google::Protobuf::Timestamp
        result[:seconds] = value.seconds
        result[:nanos] = value.nanos
      else
        result[key] = value
      end
    end
    flattened_usage.transform_keys { |k| usage_to_semconv_field_map[k] || k }
  end

  # Any general testing, logs, metrics you want to do in dev and/or ppe goes here
  # or can be overwritten by subclasses
  def publish_non_prod_usage(usage)
    GitHub.logger.info(
      "Testing Codespaces Meuse billing message handler",
      {
        "code.namespace" => self.class.name,
        "code.function" => "publish_non_prod_usage",
        "gh.codespaces.plan.id" => billing_message.codespace_plan_id,
        "gh.codespaces.billing_message.id" => billing_message.id,
      }.merge(transform_usage_for_splunk(usage)),
    )
  end
end
