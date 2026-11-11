# typed: true
# frozen_string_literal: true

# Partials/components rendered from anywhere except Discussions#show use this.
class Discussions::NullShowStats
  def record_distribution(_name)
    yield
  end

  def record_render(_renderable_name)
    yield
  end
end
