# typed: strict
# frozen_string_literal: true

module User::CopilotMonitoredUserDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { User }

  included do
    T.bind(self, T.class_of(User))

    has_one :copilot_monitored_user,
      class_name: "CopilotContentSafety::MonitoredUser",
      inverse_of: :user
  end
end
