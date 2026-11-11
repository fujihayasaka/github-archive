# typed: strict
# frozen_string_literal: true

class ResilientBlockedSettings < BlockedSettings
  include ResilienceHelper
  include ActionView::Helpers::CaptureHelper

  Elem = type_member { { fixed: Symbol } }

  sig { params(owner: T.any(Business, Organization, User)).void }
  def initialize(owner)
    super(owner)
  end

  sig { returns(T::Array[Symbol]) }
  memoize def blockers
    # If the database is unreachable, then fail closed by blocking on all blocking settings
    with_database_error_fallback(fallback: BLOCKING_SETTINGS.keys) do
      super
    end
  end
end
