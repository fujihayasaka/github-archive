# typed: true
# frozen_string_literal: true

class Codespaces::Billing::MeuseMessageHandler < Codespaces::Command
  extend T::Sig
  include GitHub::Memoizer

  abstract!

  class UnimplementedError < StandardError; end

  POST_PERFORM_JOBS_DELAY = 15.minutes

  attr_reader :billing_message, :tracked_usage, :billing_entry

  def initialize(billing_message:, tracked_usage:, billing_entry:, **kwargs)
    @billing_message = billing_message
    @tracked_usage = tracked_usage
    @billing_entry = billing_entry

    post_initialize(
      **T.unsafe({ billing_message:, tracked_usage:, billing_entry:, **kwargs })
    )
  end

  def perform
    return unless should_publish?

    if should_test_non_prod?
      test_non_prod_usage(transform_usage)
      post_perform
      return
    end

    if billing_message.vscs_target.to_sym == :production
      GitHub.dogstats.increment("codespaces.billing_usage.dispatched.count", tags: ["class:#{self.class.name&.underscore}"])
      result = publish_usage(transform_usage)
      post_perform
      result
    end
  end

  private

  # This should be overridden by subclasses
  def post_initialize(billing_message:, tracked_usage:, billing_entry:, **kwargs); end

  # This should be overridden by subclasses
  def post_perform; end

  def pre_should_publish?
    # This should be overridden by subclasses, default to true
    # Put things in here that you expect to return quickly
    true
  end

  def should_test_non_prod?
    # don't publish if feature flag is off
    return false unless GitHub.flipper[:codespaces_billing_test_non_prod].enabled?

    # don't publish ppe/dev usage if vscs_target is production
    return false if billing_message.vscs_target.to_sym == :production

    true
  end

  # non-vscs_target specific checks go here
  memoize def should_publish?
    return false if !pre_should_publish?

    # Use the billable_owner method on the org/user to handle delegating to businesses or other special cases
    billing_billable_owner = billing_entry.billable_owner&.billable_owner
    return false if billing_billable_owner.nil?
    return false if billing_billable_owner.free_codespace_use_enabled?
    return false if billing_entry.billable_owner.free_codespace_use_enabled? && GitHub.flipper[:codespaces_billable_owner_free_direct_check].enabled?(billing_entry.billable_owner)
    return false unless billing_entry.for_codespace? || billing_entry.for_prebuild?
    true
  end

  memoize def transform_usage
    custom_fields = {}
    custom_fields["repository.id"] =  billing_entry.repository_id

    payload = {
      product_name: "codespaces",
      product_sku_name: product_sku_name,
      account_id: billing_entry.billable_owner_id,
      usage_at: billing_message.period_end,
      usage_uuid: GitHub::Billing::MeteredProduct.usage_uuid(unique_billing_identifier),
      source_uri: billing_message.source_uri,
      custom_fields: custom_fields,
    }
    payload.deep_merge(post_transform_usage)
  end

  def post_transform_usage
    # This should be overridden by subclasses if they need to transform the usage additionally
    {}
  end

  sig { abstract.void }
  def product_sku_name; end

  sig { abstract.void }
  def unique_billing_identifier; end

  sig { abstract.params(usage: T.untyped).void }
  def publish_usage(usage); end

  # Any general testing, logs, metrics you want to do in dev and/or ppe goes here
  # or can be overwritten by subclasses
  def test_non_prod_usage(usage)
    usage_to_semconv_field_map = {
      "repository.id" => "gh.repo.id",
      :quantity => "gh.codespaces.billing_message.quantity",
      :actor_id => "gh.codespaces.owner_id",
      :product_name => "gh.codespaces.billing_message.product_name",
      :product_sku_name => "gh.codespaces.billing_message.product_sku_name",
      :account_id => "gh.codespaces.billable_owner_id",
      :usage_at => "gh.codespaces.billing_message.usage_at",
      :usage_uuid => "gh.codespaces.billing_message.usage_uuid",
      :source_uri => "gh.codespaces.billing_message.source_uri",
    }

    semconv_fields = usage.except(:custom_fields).transform_keys { |k| usage_to_semconv_field_map[k] || k }
    semconv_fields.merge!(usage[:custom_fields].transform_keys { |k| usage_to_semconv_field_map[k] || k })

    GitHub.logger.info(
      "Testing Codespaces Meuse billing message handler",
      {
        "code.namespace" => self.class.name,
        "code.function" => "test_non_prod_usage",
        "gh.codespaces.plan.id" => billing_message.codespace_plan_id,
        "gh.codespaces.billing_message.id" => billing_message.id,
      }.merge(semconv_fields),
    )
  end
end
