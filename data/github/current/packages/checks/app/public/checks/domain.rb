# typed: strict
# frozen_string_literal: true

module Checks
  class Domain < GH::Domain::Base
    accessor Checks::Domain::CheckRuns
    accessor Checks::Domain::CheckSuites
  end
end
