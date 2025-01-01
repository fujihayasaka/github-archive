# typed: strict
# frozen_string_literal: true

module Events
  extend GH::Domain::Registration

  register_domain Events::Domain
end
