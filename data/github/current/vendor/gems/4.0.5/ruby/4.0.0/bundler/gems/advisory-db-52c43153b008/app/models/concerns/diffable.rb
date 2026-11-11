# frozen_string_literal: true

module Diffable
  def diff
    return @diff if defined? @diff

    left = {}
    right = {}

    changeset.each do |key, (left_value, right_value)|
      left[key] = left_value
      right[key] = right_value
    end

    @diff = Diffy::Diff.new(NormalYAML.dump(left), NormalYAML.dump(right))
  end
end
