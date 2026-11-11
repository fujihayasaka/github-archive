# typed: true
# frozen_string_literal: true

class Actions::CacheItemComponent < ApplicationComponent
  def initialize(cache_item:, current_repository:, current_user:)
    @cache_item = cache_item
    @current_repository = current_repository
    @current_user = current_user
  end

  private

  attr_reader :cache_item, :current_repository, :current_user

  def cache_item_name
    cache_item[:key]
  end

  def cache_item_size
    cache_item[:size_in_bytes]
  end

  def cache_item_last_created_at
    cache_item[:created_at]
  end

  def cache_item_last_used_at
    cache_item[:last_accessed_at]
  end

  def cache_item_ref
    cache_item[:ref]
  end

  def cache_item_id
    cache_item[:id]
  end

  memoize def cache_writable?
    current_repository.writable_by?(current_user)
  end

  def middle_truncation(cache_item_name)
    if cache_item_name.length > 50
      "#{cache_item_name[0..25]}... #{cache_item_name[-25..-1]}"
    else
      cache_item_name
    end
  end
end
