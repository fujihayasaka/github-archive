# typed: true
# frozen_string_literal: true

module ReleasesHelper

  # Paginate all tags in the repository.
  #
  # after - The last tag name on the current page.
  # limit - Number of tags to include on each page.
  #
  # Returns HTML for the pagination thing.
  def tag_paginate(after, num_releases, limit = Releases::Public::PER_PAGE)
    # since sorbet cannot find current_repository, we need to add T.bind(self, T.untyped) to disable type checking
    T.bind(self, T.untyped)
    paginate Release.pagination_for_tags(current_repository, after, limit, num_releases), limit
  end

  private def paginate(pagination, limit)
    # since sorbet cannot find raw_paginate, we need to add T.bind(self, T.untyped) to disable type checking
    T.bind(self, T.untyped)
    options = {}

    options[:next_index] = pagination.next_index

    if pagination.previous_page?
      options[:prev_url] = if tag = pagination.previous_tag
        { after: tag }
      else
        {}
      end
    end

    if pagination.next_page?
      options[:next_url] = { after: pagination.next_tag }
    else
      options[:on_last_page] = true
    end

    raw_paginate pagination.total_size, limit, pagination.current_page, options
  end

  # Filter an array of Release objects down to only those with valid tags. A
  # valid tag is one that eventually points to a commit. Tags that point to
  # blobs or trees are omitted.
  #
  # releases - Array of Release objects.
  #
  # Returns a filtered Array of Releases objects.
  def releases_with_valid_tags(releases)
    releases.select { |rel| rel.tag.commit? }
  end
end
