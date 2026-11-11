# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class StatusState < Platform::Enums::Base
      description "The possible commit status states."

      ::Status::States.each do |state|
        value state.upcase, "Status is #{::StatusCheckConfig.adjective_state(state)}.", value: state
      end
    end
  end
end
