# typed: true
# frozen_string_literal: true

class ActionsCacheUsage
  sig { returns(Integer) }
  def total_active_caches_count; end

  sig { returns(Integer) }
  def total_active_caches_size; end
end
