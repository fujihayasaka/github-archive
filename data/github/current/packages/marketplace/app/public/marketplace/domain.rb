# typed: strict
# frozen_string_literal: true

module Marketplace
  class Domain < GH::Domain::Base

    include GitHub::Memoizer

    sig { returns(RepositorySettings) }
    memoize def repository_settings # rubocop:disable GitHub/DocumentationDomainMethod
      RepositorySettings.new(caller_service)
    end

    skip_decoration :repository_settings
  end
end
