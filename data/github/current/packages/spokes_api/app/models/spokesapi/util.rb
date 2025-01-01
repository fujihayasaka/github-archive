# typed: true
# frozen_string_literal: true

module SpokesAPI
  module Util
    extend self

    OID_REGEXP = /\A[a-f0-9]{40}\z/

    # Check if a given string is a valid 40 char OID
    #
    # oid - String to check
    #
    # Returns true when oid is a valid oid
    def valid_oid?(oid)
      oid.is_a?(String) && oid.size == 40 && OID_REGEXP.match?(oid)
    end
  end
end
