# typed: strict
# frozen_string_literal: true

module Restorables
  class Domain < GH::Domain::Base
    accessor Restorables::Domain::VisibilityChangedRepositories
  end
end
