# typed: true
# frozen_string_literal: true

module BypassCheckHelper
  sig do
    params(source: RuleEngine::Types::RuleSource).
    returns(T::Boolean)
  end
  def self.merge_queue_can_bypass(source)
    # Merge queue is globally enabled for this instance
    return false unless GitHub.merge_queues_enabled?
    return false unless GitHub.merge_queue_bot.present?

    GitHub.enterprise? || \
      source.plan_supports?(:merge_queue) || \
      (source.is_a?(Organization) && source.plan_supports?(:merge_queue, visibility: :public)) || \
      (source.is_a?(Business) && source.plan.supports?(:merge_queue, org: true, visibility: :public)) || \
      source.feature_flag_enabled?(:merge_queue, memoize: false, default: false)
  end
end
