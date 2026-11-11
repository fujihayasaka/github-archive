# typed: true
# frozen_string_literal: true

class RepositoryPushRefSorter
  attr_reader :refs, :ordered_refs, :partitioned_refs

  def initialize(refs)
    @refs = refs
    @ordered_refs ||= refs.sort { |a, b| T.must(b[2]) <=> T.must(a[2]) }
    @partitioned_refs ||= @ordered_refs.partition do |(ref, _before, _after)|
      ref =~ %r|^refs/tags|
    end
  end

  def tags
    partitioned_refs[0]
  end

  def branches
    partitioned_refs[1]
  end

  def processed_refs
    # Ignore tags if the push has more than 3 tags.
    tags.size > 3 ? branches : ordered_refs
  end
end
