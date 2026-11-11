# typed: strict
# frozen_string_literal: true

module ArtifactRegistry
  extend GH::Domain::Registration

  register_domain ArtifactRegistry::Domain
end
