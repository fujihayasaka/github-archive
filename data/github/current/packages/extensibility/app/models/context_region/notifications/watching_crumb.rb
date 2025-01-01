# typed: strict
# frozen_string_literal: true

module ContextRegion
  module Notifications
    class WatchingCrumb < Crumb
      sig { override.returns(String) }
      def label
        "Watching"
      end

      sig { override.returns(Crumb) }
      def parent
        NotificationsCrumb.new
      end
    end
  end
end
