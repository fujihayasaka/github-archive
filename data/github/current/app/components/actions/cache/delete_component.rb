# typed: true
# frozen_string_literal: true

class Actions::Cache::DeleteComponent < ApplicationComponent
  def initialize(label:, path:, cache_id:)
    @label = label
    @path = path
    @cache_id = cache_id
  end

  private

  attr_reader :label, :path, :cache_id
end
