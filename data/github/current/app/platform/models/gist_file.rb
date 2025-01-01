# typed: true
# frozen_string_literal: true

class Platform::Models::GistFile
  attr_reader :gist, :tree_entry

  def initialize(gist, tree_entry)
    @gist = gist
    @tree_entry = tree_entry
  end
end
