# typed: true
# frozen_string_literal: true

module SecurityCenterHelper
  def self.sort_items_with_counts(items)
    items
      .select { |obj| obj[:count] > 0 }
      .sort do |a, b|
        # first try sorting by count in descending order (most to least)
        comp = (b[:count] <=> a[:count])
        if comp == 0
          # if counts are equal, sort by name in ascending order (a -> z)
          comp = a[:label].casecmp(b[:label])
        end
        comp
      end
  end
end
