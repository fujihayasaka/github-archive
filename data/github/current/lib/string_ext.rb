# typed: false
# frozen_string_literal: true

require "fast_blank"

class String
  alias blank? blank_as?
end
