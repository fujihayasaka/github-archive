# typed: strict
# frozen_string_literal: true

module DependencyGraph
  class Domain < GH::Domain::Base
    # This domain should be responsible for wrapping access to DG services in future, ideally abstracting away the
    # actual service arrangement and focusing on the monolith's usage contract.
    #
    # See: https://thehub.github.com/epd/engineering/products-and-services/dotcom/domain-isolation/domain-interface/
  end
end
