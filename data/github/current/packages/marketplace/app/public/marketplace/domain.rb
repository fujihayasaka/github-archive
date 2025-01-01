# typed: strict
# frozen_string_literal: true

module Marketplace
  class Domain < GH::Domain::Base
    accessor Marketplace::Domain::RepositorySettings
  end
end
