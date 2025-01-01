# typed: strict
# frozen_string_literal: true

module TradeControls
  class ComplianceCheckJob < ApplicationJob
    extend T::Sig

    queue_as :trade_controls

    RETRYABLE_ERRORS = T.let([
      ActiveRecord::RecordNotUnique,
      *Resiliency::Response::UnavailableExceptions, # Recoverable exceptions
    ].freeze, T::Array[T.class_of(StandardError)])

    retry_on_dirty_exit

    RETRYABLE_ERRORS.each do |error|
      retry_on error, wait: :polynomially_longer, attempts: 2 do |_job, error|
        Failbot.report(error)
      end
    end

    discard_on ActiveRecord::RecordNotFound

    sig { params(user_id: Integer, ip: T.nilable(String), email: T.nilable(String), location: T.nilable(T::Hash[Symbol, String]), event_source: T.nilable(String)).void }
    def perform(user_id, ip: nil, email: nil, location: nil, event_source: nil)
      return if ip.nil? && email.nil? && location.nil?

      compliance = Compliance.for(ip: ip, email: email, location: location, event_source: event_source)
      return unless compliance.violation?

      user = User.find_by(id: user_id)
      return unless user.present?

      unless user.has_full_trade_restrictions?
        # record the start time so we monitor how long it takes to complete a request
        start_time = GitHub::Dogstats.monotonic_time
        with_write do
          user.trade_controls_restriction.enforce!(compliance: compliance)
        end
        tags = ["jid:#{self.job_id}", "compliance:#{compliance.class.name}"]
        GitHub.dogstats.timing_since("compliance_check_job.enforce.time", start_time, tags: tags)
      end
    end
  end
end
