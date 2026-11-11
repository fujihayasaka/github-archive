# typed: strict
# frozen_string_literal: true

module Admin
  extend GH::Domain::Registration

  register_domain Admin::Domain
end
