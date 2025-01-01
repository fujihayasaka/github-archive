# typed: strict
# frozen_string_literal: true

module Stars
  StarrableEntityTypes = T.type_alias { T.any(Repository, Gist, Topic) }
end
