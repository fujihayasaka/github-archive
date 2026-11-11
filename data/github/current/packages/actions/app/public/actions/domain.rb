# typed: strict
# frozen_string_literal: true

module Actions
  class Domain < GH::Domain::Base
    accessor Actions::Domain::Rulesets
  end
end
