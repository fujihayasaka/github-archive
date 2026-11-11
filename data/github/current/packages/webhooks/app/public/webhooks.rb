# typed: strict
# frozen_string_literal: true

module Webhooks
  extend GH::Domain::Registration

  register_domain Webhooks::Domain
end
