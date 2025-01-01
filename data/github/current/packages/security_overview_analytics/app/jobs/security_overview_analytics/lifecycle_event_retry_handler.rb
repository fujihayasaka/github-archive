# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module LifecycleEventRetryHandler
    extend T::Sig
    extend T::Helpers

    abstract!

    # This mixin can only be included in classes that extend HydroMesageJob.
    requires_ancestor { HydroMessageJob }

    RETRYABLE_ERRORS = T.let([
      ActiveRecord::RecordNotFound, # replication lag
      ActiveRecord::Deadlocked, # DB deadlock
      Freno::Error, # All things Freno
      *Resiliency::Response::UnavailableExceptions, # DB unavailable
    ], T::Array[T.class_of(StandardError)])

    sig { params(base: Module).void }
    def self.included(base)
      T.unsafe(base).retry_on(*RETRYABLE_ERRORS, delay: :polynomially_longer)
    end
  end
end
