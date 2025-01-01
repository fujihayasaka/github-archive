# typed: strict
# frozen_string_literal: true

module Notifyd
  module Email
    class NoReplyAddress < T::Struct
      extend T::Sig

      prop :name, String
      prop :handle, String

      sig { returns(String) }
      def to_s
        "#{name} <#{handle}@noreply.#{GitHub.urls.smtp_domain}>"
      end
      alias_method :serialize, :to_s
    end
  end
end
