# typed: true
# frozen_string_literal: true

module Users
  module Settings
    class InteractionLimitsNavComponent < ApplicationComponent
      delegate_missing_to :@item

      def initialize(expires_at:, **system_arguments)
        @expires_at = expires_at
        @system_arguments = system_arguments
        @item = T.unsafe(Primer::Beta::NavList::Item).new(
          description_scheme: :inline, **@system_arguments
        )
      end

      private

      attr_reader :expires_at

      def time_remaining
        distance_of_time_in_words(Time.current, expires_at).gsub(/(about|less than)\s/, "")
      end
    end
  end
end
