# typed: strict
# frozen_string_literal: true

require "digest"
require "sorbet-runtime"

# Docs in https://github.com/github/in-product-messaging/blob/main/hawaii_exp.md
module HawaiiExperimentHelper
  extend ActiveSupport::Concern
  include Kernel

  sig do
    params(
      experiment_id: String,
      user_id: T.nilable(T.any(String, Integer)),
      variant_count: Integer
    ).returns(Integer)
  end
  def hawaii_experiment_variant(experiment_id:, user_id:, variant_count:)
    return -1 unless FeatureFlag.vexi.enabled?(:hawaii_exp, default: false)
    return -1 unless experiment_setup_valid?(experiment_id: experiment_id, user_id: user_id, variant_count: variant_count)

    hash = T.let(Digest::SHA256.hexdigest("#{experiment_id}:#{user_id}"), String)
    hash_num = T.must(hash[0..7]).to_i(16)
    variant = hash_num % variant_count

    variant
  rescue StandardError => e
    Failbot.report(e, catalog_service: "github/in_product_messaging")
    -1
  end

  private

  sig do
    params(
      experiment_id: String,
      user_id: T.nilable(T.any(String, Integer)),
      variant_count: Integer
    ).returns(T::Boolean)
  end
  def experiment_setup_valid?(experiment_id:, user_id:, variant_count:)
    return false unless HawaiiExperiments::HAWAII_EXPERIMENT_IDS.include?(experiment_id)
    return false unless variant_count.positive?
    return false if user_id.nil?

    true
  end
end
