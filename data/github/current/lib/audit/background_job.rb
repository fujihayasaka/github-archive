# typed: true
# frozen_string_literal: true

require "delegate"

module Audit
  # Decorator around an Audit service, which will build the payload from the
  # inner_service and queue up the Audit for a background job worker to do the actual auditing.
  class BackgroundJob < SimpleDelegator
    attr_reader :service
    # Public: Create the Audit adapter wrapping the service.
    #
    # service - Audit service
    def initialize(service)
      super
      @inline = false
      @service = service
    end

    # Public: Queue the actual log.
    #
    # action  - A String key identifying the action.
    # payload - The Hash of data that is sent over as JSON.  See
    #           Audit::Service#log
    #
    # Returns true.
    def log(action, payload)
      if @inline
        T.bind(self, T.untyped)
        super # We don't need the prepared payload here since the delegate will prepare it for us.
      else
        prepared_payload = service.build_payload(action, payload)
        service.ensure_staff_action_privacy(action, prepared_payload)
        ::LogAuditEntryJob.perform_later(action, prepared_payload)
      end

      true
    end

    # Public: Used to run the job in line, will raise a LocalJumpError unless
    # called with a block.
    def inline
      old_inline = @inline
      @inline = true
      yield
    ensure
      @inline = old_inline
    end

    def inline?
      @inline
    end
  end
end
