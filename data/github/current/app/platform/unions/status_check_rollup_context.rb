# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class StatusCheckRollupContext < Platform::Unions::Base
      description "Types that can be inside a StatusCheckRollup context."

      possible_types(
        Objects::StatusContext,
        Objects::CheckRun,
      )
    end
  end
end
