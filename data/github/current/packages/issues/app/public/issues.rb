# typed: strict
# frozen_string_literal: true

module Issues
  extend GH::Domain::Registration

  register_domain Issues::Domain
end
