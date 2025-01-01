# typed: true
# frozen_string_literal: true

module GitHub
  module LDAP
    module Instrumentable
      def ldap_fields_changed
        @ldap_fields_changed ||= []
      end

      private

      # Internal: appends +field+ to the list of LDAP fields that have changed
      def log_ldap_sync!(field)
        return if field.nil?
        ldap_fields_changed << field
      end
    end
  end
end
