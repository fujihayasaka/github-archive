# typed: true
# frozen_string_literal: true

module Codespaces
  class IdleTimeoutComponent < ApplicationComponent
    def initialize(entity:, update_idle_timeout_path:)
      @entity = entity
      @update_idle_timeout_path = update_idle_timeout_path
    end

    def description
      "A codespace will suspend after a period of inactivity. You can specify a default idle timeout value, which will apply to all codespaces created after the default is changed. You will be charged for the entire time your codespace is running, even if it is idle."
    end

    memoize def upper_limit
      Codespaces::Vscs::MAX_IDLE_TIME / 1.minute
    end

    memoize def lower_limit
      Codespaces::Vscs::MIN_IDLE_TIME / 1.minute
    end

    def value
      @entity.codespace_default_idle_timeout
    end

    def upper_limit_error
      "Timeout must be #{upper_limit} minutes or less."
    end

    def lower_limit_error
      "Timeout must be #{lower_limit} minutes or more."
    end
  end
end
