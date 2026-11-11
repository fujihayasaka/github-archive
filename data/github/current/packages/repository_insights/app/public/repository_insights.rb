# typed: strict
# frozen_string_literal: true

module RepositoryInsights
  class TwirpError < StandardError; end

  extend GH::Domain::Registration

  register_domain RepositoryInsights::Domain
end
