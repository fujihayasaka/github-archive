# typed: strict
# frozen_string_literal: true

module RulesInsights
  class TwirpError < StandardError; end

  extend GH::Domain::Registration

  register_domain RulesInsights::Domain
end
