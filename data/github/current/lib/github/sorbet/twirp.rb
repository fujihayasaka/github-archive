# typed: true
# frozen_string_literal: true

require "twirp"

class Twirp::ClientResp
  extend T::Generic

  Elem = type_member
end
