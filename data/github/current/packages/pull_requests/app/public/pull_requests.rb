# typed: strict
# frozen_string_literal: true

module PullRequests
  extend GH::Domain::Registration

  register_domain PullRequests::Domain
end
