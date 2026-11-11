# typed: strict
# frozen_string_literal: true

module Actions
  extend GH::Domain::Registration

  register_domain Actions::Domain
end
