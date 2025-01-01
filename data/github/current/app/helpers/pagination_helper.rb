# typed: true
# frozen_string_literal: true

module PaginationHelper
  def will_paginate(collection, options = {})
    unless options.key?(:renderer)
      options = options.merge(renderer: WillPaginateRenderer)
    end
    super(collection, options)
  end
end
