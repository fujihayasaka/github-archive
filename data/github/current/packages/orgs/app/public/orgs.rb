# typed: strict
# frozen_string_literal: true

module Orgs
  extend GH::Domain::Registration

  register_domain Orgs::Domain
end
