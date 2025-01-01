# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class SecurityIncidentScreeningStatus < Platform::Inputs::Base
      description "Specifies a trade screening status and a reason for screening status change"
      visibility :internal

      argument :status, String, "Trade screening status", required: true
      argument :reason, String, "Reason for change to screening status", required: true
    end
  end
end
