# typed: strict
# frozen_string_literal: true

module ExternalIdentities
  extend GH::Domain::Registration

  register_domain ExternalIdentities::Domain
end
