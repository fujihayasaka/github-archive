# typed: true
# frozen_string_literal: true

module Audit
  # A module of helper methods so classes can audit themselves.
  module Model
    include Kernel

    # Public: Logs audit data for this object.
    #
    # key - String suffix of the Audit key.  See #audit_prefix.
    #
    # Returns nothing.
    def audit(key, options = nil)
      audit_service.log("#{audit_prefix}.#{key}") do
        opts = options
        opts ||= yield if block_given?
        opts ? audit_options.merge(opts) : audit_options.dup
      end
    end

    # Internal: Defines the Audit key prefix for everything logged through this
    # object.
    #
    # Returns a String.
    def audit_prefix
      :model
    end

    # Internal: Defines the Audit options that are logged for every call.
    #
    # Returns a Hash.
    def audit_options
      {}
    end

    # Internal: Defines the Audit::Service instance.
    #
    # Returns an Audit::Service.
    def audit_service
      @audit_service ||= GitHub.audit
    end

    def audit_service=(value)
      @audit_service = value
    end
  end
end
