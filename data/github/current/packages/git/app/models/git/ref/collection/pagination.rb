# typed: true
# frozen_string_literal: true

# Pagination based on ref names.
#
# TODO Once ref (mainly tag) pagination is moved to GraphQL,
#   it is going to be cursor-based and implemented in the GraphQL layer.
#   At that point, this pagination logic can disappear.
module Git::Ref::Collection::Pagination
  extend T::Helpers

  requires_ancestor { Git::Ref::Collection }


  def page(options = {})
    tag_names = self.names

    options[:limit] ||= 100
    index, lower = 0, 0
    if after = options[:after]
      index = tag_names.index(after.b) || -1
      lower = index + 1
    end
    upper = options[:limit] - 1 + lower

    tag_names[lower..upper].map { |name| find(name) }.tap do |refs|
      T.bind(self, Git::Ref::Collection)
      self.class.preload_target_objects(refs)
    end
  end

  def paginate(after, limit, num_releases)
    Git::Ref::Collection::Pagination.paginate_tag_names(self.names, after, limit, num_releases)
  end

  def self.paginate_tag_names(tag_names, after, limit, num_releases)
    page_count = (tag_names.size / limit.to_f).ceil

    # Index of the first tag on the next page
    next_index = tag_names.include?(after) ? tag_names.index(after) + 1 : limit
    curr_page  = (next_index ? (next_index - 1) / limit : 0) + 1

    next_tag = next_index < tag_names.size ? tag_names[next_index - 1] : nil
    prev_index = next_index - num_releases - limit - 1
    prev_tag = prev_index >= 0 ? tag_names[prev_index] : nil

    Info.new(page_count.to_i, curr_page, next_index, next_tag, prev_tag, tag_names.size, limit)
  end

  class Info
    attr_accessor :page_count, :current_page, :next_index, :next_tag, :previous_tag, :total_size, :limit

    def initialize(page_count, current_page, next_index, next_tag, previous_tag, total_size, limit)
      @page_count     = page_count.to_i
      @current_page   = current_page.to_i
      @next_index     = next_index.to_i
      @next_tag       = next_tag
      @previous_tag   = previous_tag
      @total_size     = total_size.to_i
      @limit          = limit.to_i
    end

    def previous_page?
      next_index > limit
    end

    def next_page?
      next_index < total_size
    end
  end
end
