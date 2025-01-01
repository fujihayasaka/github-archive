# typed: true
# frozen_string_literal: true

class Platform::Models::GistStafftoolsInfo
  attr_reader :gist

  def initialize(gist)
    @gist = gist
  end
end
