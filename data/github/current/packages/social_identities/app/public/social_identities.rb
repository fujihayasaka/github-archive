# typed: strict
# frozen_string_literal: true

module SocialIdentities
  extend GH::Domain::Registration

  register_domain SocialIdentities::Domain
end
