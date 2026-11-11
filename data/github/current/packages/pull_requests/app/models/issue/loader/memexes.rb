# typed: true
# frozen_string_literal: true

class Issue::Loader::Memexes < Issue::Loader::Base
  def initialize(context, memex_ids: [])
    @context = context
    @memex_ids = memex_ids
  end

  def self.load_for(context, memex_ids: [])
    super new(context, memex_ids: memex_ids)
  end

  def self.preload_for(context, memexes: [])
    T.unsafe(new(context)).preload(memexes)
  end

  def load
    return {} unless @memex_ids.any?

    MemexProject.strict_loading.
      where(id: @memex_ids).
      index_by(&:id)
  end
end
