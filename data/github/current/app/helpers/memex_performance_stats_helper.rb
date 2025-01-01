# typed: true
# frozen_string_literal: true

module MemexPerformanceStatsHelper
  # These buckets are determined with reference to the following distribution:
  # https://data.githubapp.com/sql/share/0ab4ebdf. If the distribution changes
  # significantly, then these buckets should be reconfigured. Whenever the
  # buckets are reconfigured, we should bump the MEMEX_METADATA_TAGS_VERSION
  # number.
  WIDTH_BUCKETS = [
    [3, :xs],
    [5, :s],
    [10, :m],
    [15, :l],
    [Float::INFINITY, :xl],
  ]

  # These buckets are determined with reference to the following distribution:
  # https://data.githubapp.com/sql/share/9f78bbbc. If the distribution changes
  # significantly, then these buckets should be reconfigured. Whenever the
  # buckets are reconfigured, we should bump the MEMEX_METADATA_TAGS_VERSION
  # number.
  HEIGHT_BUCKETS = [
    [20, :xs],
    [50, :s],
    [150, :m],
    [300, :l],
    [Float::INFINITY, :xl],
  ]

  # These buckets are determined with reference to the following distribution:
  # https://data.githubapp.com/sql/share/565929c6. If the distribution changes
  # significantly, then these buckets should be reconfigured.
  MEMEX_WITHOUT_LIMITS_HEIGHT_BUCKETS = [
    [20, :xs],
    [50, :s],
    [2_000, :m],
    [10_000, :l],
    [Float::INFINITY, :xl],
  ]

  def self.height_bucket(value)
    self.bucketed_value(value, HEIGHT_BUCKETS)
  end

  def self.width_bucket(value)
    self.bucketed_value(value, WIDTH_BUCKETS)
  end

  def self.column_count_by_type(columns, key_prefix: "")
    columns_by_type = columns.group_by(&:data_type)

    MemexProjectColumn.data_types.each_with_object({}) do |(type_name, type_id), result|
      if columns_by_type.has_key?(type_name) && type_id == MemexProjectColumn.data_types[:single_select]
        # Since the Status column is a special type of single-select column,
        # count it's occurence separately (and in addition to the general
        # count of single-select columns).
        result["#{key_prefix}status"] = columns_by_type[type_name].count(&:status?)
      end

      result["#{key_prefix}#{type_name}"] = columns_by_type.fetch(type_name, []).length
    end
  end

  def self.bucketed_value(value, buckets)
    buckets.find { |(upper_bound, _)| value <= upper_bound }.second.to_s
  end
end
