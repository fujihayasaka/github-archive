# typed: false
# frozen_string_literal: true

module Configurable
  module ActionsRetentionLimit
    include Instrumentation::Model
    Error = Class.new(StandardError)

    KEY = "actions_retention_limit".freeze
    MIN = 1.freeze
    MAX = 400.freeze
    DEFAULT = 90.freeze
    DOTCOM_PUBLIC_REPO_MAX = 90.freeze

    def actions_retention_limit
      value = config.get(KEY) || DEFAULT
      limitted_value = [value.to_i, max_allowed_actions_retention_limit].min
      [limitted_value, MIN].max
    end

    def max_allowed_actions_retention_limit
      # actions_retention_limit is bound by configuration owner's value and our hard max- 90 for public repos on dotcom, 400 for everything else
      [owner_limit, entity_type_max_retention_limit].min
    end

    def entity_type_max_retention_limit
      # we allow up to 90 for public repos on dotcom, 400 for everything else
      (!GitHub.enterprise? && is_a?(Repository) && public) ? DOTCOM_PUBLIC_REPO_MAX : MAX
    end

    def set_actions_retention_limit(limit:, actor:)
      raise Error.new("Retention value must be between #{MIN} and #{max_allowed_actions_retention_limit}.") unless limit.between?(MIN, max_allowed_actions_retention_limit)
      config.set(KEY, limit.to_s, actor)

      instrument "set_actions_retention_limit", actor: actor, limit: limit
    end

    private

    def owner_limit
      @owner_limit ||= configuration_owner&.respond_to?(:actions_retention_limit) ? configuration_owner.actions_retention_limit : MAX
    end
  end
end
