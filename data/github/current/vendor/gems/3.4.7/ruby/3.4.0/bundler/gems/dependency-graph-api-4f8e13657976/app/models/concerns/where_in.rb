# This helper provides `.where_in`/`.where_not_in`, which allow
# querying a database table using an `IN/NOT IN` clause for multiple
# columns and values.
# These methods are useful when you need to find records
# that match multiple conditions on large datasets.
#
# Usage:
#   Model.where_in([:id, :status], [[1, 'laughing'], [2, 'staying'], [3, 'alive']])
#
module WhereIn
  extend ActiveSupport::Concern

  class_methods do
    def where_in(columns, values)
      if values.empty?
        self.where("FALSE")
      else
        placeholder = "(" + Array.new(columns.length, "?").join(",") + ")"
        placeholders = Array.new(values.length, placeholder).join(",")
        self.where(
          "(" + columns.join(",") + ") IN (" + placeholders + ")",
          *values.flatten
        )
      end
    end

    def where_not_in(columns, values)
      if values.empty?
        self.where("TRUE")
      else
        placeholder = "(" + Array.new(columns.length, "?").join(",") + ")"
        placeholders = Array.new(values.length, placeholder).join(",")
        self.where(
          "(" + columns.join(",") + ") NOT IN (" + placeholders + ")",
          *values.flatten
        )
      end
    end
  end
end
