# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectV2StatusUpdateStatus < Platform::Enums::Base
      description "The possible statuses of a project v2."

      value "INACTIVE", "A project v2 that is inactive."
      value "ON_TRACK", "A project v2 that is on track with no risks."
      value "AT_RISK", "A project v2 that is at risk and encountering some challenges."
      value "OFF_TRACK", "A project v2 that is off track and needs attention."
      value "COMPLETE", "A project v2 that is complete."
    end
  end
end
