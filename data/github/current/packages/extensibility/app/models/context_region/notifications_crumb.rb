# typed: strict
# frozen_string_literal: true

module ContextRegion
  class NotificationsCrumb < Crumb
    sig { override.returns(String) }
    def label
      "Notifications"
    end

    sig { override.returns(T.nilable(Symbol)) }
    def path_name
      :global_notifications_path
    end
  end
end
