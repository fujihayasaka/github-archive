# typed: false
# frozen_string_literal: true

module GitHub::FieldTruncator
  def truncate_field(field, limit)
    if self[field].present? && self[field].bytesize > limit
      self[field] = self[field].truncate_bytes(limit, omission: "")

      GitHub.dogstats.increment(
        "field_truncator",
        tags: ["class:#{self.class.name}", "field:#{field}"]
      )
    end
  end
end
