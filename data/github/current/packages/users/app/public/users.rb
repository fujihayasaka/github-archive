# typed: strict
# frozen_string_literal: true

module Users
  extend GH::Domain::Registration

  register_domain Users::Domain
end
