# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class AdvisoryCreditState < Platform::Enums::Base
      description "The possible states of an advisory credit."

      visibility :internal


      value "PENDING", "Credit that has been neither accepted nor declined.", value: "pending"
      value "ACCEPTED", "Credit that has been accepted by its recipient.", value: "accepted"
      value "DECLINED", "Credit that has been declined by its recipient.", value: "declined"
    end
  end
end
