# typed: strict
# frozen_string_literal: true

module Stars
  extend GH::Domain::Registration

  StarrableEntityTypes = T.type_alias { T.any(Repository, Gist, Topic) }

  register_domain Stars::Domain
end
