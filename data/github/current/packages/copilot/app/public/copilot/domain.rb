# typed: strict
# frozen_string_literal: true

module Copilot
  class Domain < GH::Domain::Base
    accessor Copilot::Domain::Settings
  end
end
