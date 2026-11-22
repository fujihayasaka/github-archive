# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module GhasSeatChecks
      # On GHES, skip GHAS seat checks during enablement and treat seats as available.
      # ghe-config app.github.ghas-seat-checks-disabled true && ghe-config-apply
      sig { returns(T::Boolean) }
      def ghas_seat_checks_disabled?
        return false unless GitHub.enterprise?
        @ghas_seat_checks_disabled == true
      end

      # Untyped: set from the ENTERPRISE_* env passthrough in environments/enterprise.rb.
      attr_writer :ghas_seat_checks_disabled
    end
  end

  extend Config::GhasSeatChecks
end
