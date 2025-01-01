# typed: true
# frozen_string_literal: true
class Actions::CacheWarningComponent < ApplicationComponent
  def initialize(cache_limit:, current_cache_size:)
    @cache_limit = cache_limit
    @current_cache_size = current_cache_size
  end

  private

  attr_reader :cache_limit, :current_cache_size

  def percentage_of_cache_used
    ((current_cache_size.to_f / cache_limit.to_f) * 100).round(2)
  end

end
