# typed: strict
# frozen_string_literal: true

module GitHub
  module Config
    module Proxima
      extend T::Sig
      extend T::Helpers

      # all Proxima stamps should be added to this list
      ALL_STAMPS = T.let(%w[
        staff-wus2-01
        prod-weu-01
        prod-sdc-01
      ].freeze, T::Array[String])

      sig { params(stamp: String).returns(T::Boolean) }
      def self.valid_stamp?(stamp)
        ALL_STAMPS.include?(stamp)
      end

      # Return the current Proxima stamp, or nil if not in Proxima
      sig { returns(T.nilable(String)) }
      def self.current_stamp
        return @current_stamp if defined?(@current_stamp)
        if GitHub.multi_tenant_enterprise?
          @current_stamp = T.let(ENV.fetch("HEAVEN_DEPLOYED_ENV", ""), T.nilable(String))
        else
          @current_stamp = T.let(nil, T.nilable(String))
        end
      end

      # If we're not in Proxima, return "dotcom"
      sig { returns(String) }
      def self.current_stamp_or_dotcom
        return T.must(@current_stamp_or_dotcom) if defined?(@current_stamp_or_dotcom)
        T.must(@current_stamp_or_dotcom = T.let(current_stamp || "dotcom", T.nilable(String)))
      end
    end
  end

  # Note: there's no need to extend this into GitHub::Config.
end
