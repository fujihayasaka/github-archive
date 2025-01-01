# typed: true
# frozen_string_literal: true

require "version_sorter"

class Git::Tag::SortedLoader < Git::Ref::Loader
  def initialize(repository, pattern: nil)
    @pattern = pattern

    super(repository, "default")
  end

  private

  attr_reader :pattern

  def load_all_refs
    Tags::Public.sorted_for(repository:, pattern:)
  rescue GitRPC::InvalidRepository, GitHub::DGit::UnroutedError
    []
  end
end
