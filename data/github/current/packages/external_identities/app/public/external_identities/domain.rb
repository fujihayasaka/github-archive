# typed: strict
# frozen_string_literal: true

module ExternalIdentities
  class Domain < GH::Domain::Base
    accessor ExternalIdentities::Domain::EntraSubjectTokens
    accessor ExternalIdentities::Domain::EmuUsers
  end
end
