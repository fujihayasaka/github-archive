# typed: true
# frozen_string_literal: true

# Controls whether we enable fail fast mode for git operations.
# Fail fast mode allows git operations to return a 429 response faster
# when the repository is under heavy load.
#
# This mode only works for pushes and fetches, not for other git operations.
module Configurable
  module FailFastMode
    extend T::Helpers

    requires_ancestor { Configurable }

    FAIL_FAST_MODE = "git.fail_fast_mode"

    sig { returns(T::Boolean) }
    def fail_fast_enabled?
      config.enabled?(FAIL_FAST_MODE)
    end

    sig { params(actor: T.anything).void }
    def enable_fail_fast(actor:)
      config.enable(FAIL_FAST_MODE, actor)
    end

    sig { params(actor: T.anything).void }
    def disable_fail_fast(actor:)
      config.delete(FAIL_FAST_MODE, actor)
    end
  end
end
