# typed: true
# frozen_string_literal: true

class MemexProject
  # A Group instance helps uniquely identify a group within a bunch of groups.
  # A Project view can be grouped by a column and when it is, the view can
  # produce a unique list of these objects.
  class Group
    include Comparable

    attr_reader :column, :title, :value, :view

    delegate :data_type, to: :column, allow_nil: true

    delegate :id, to: :view, allow_nil: true, prefix: true

    # we want to expose column.name as Group#column_name and not Group#name to be more clear.
    # Group#name might be confusing with Group#title and Group#view_group_id already existing.
    delegate :name, to: :column, allow_nil: true, prefix: true

    def initialize(column: nil, title: "", value: nil, view: nil)
      @column = column
      @title  = title.to_s
      @value  = value
      @view   = view
    end

    # Returns a string that can be used as a unique identifier for this group.  It is based strictly off the
    # synthetic id for the column (user defined would be ID, non-user defined is the name)
    # and the value unique to this group. This ID is not globally unique, but is unique within the context of
    # a view.
    def view_group_id
      Base64.urlsafe_encode64([view_id, column_id, value].to_json)
    end

    def hash
      [view_id, column_id, value].hash
    end

    # Defines what to sort the group by when compared to other groups with the same column data_type.
    def sort_value
      if column&.date? || column&.number?
        value
      elsif column&.iteration?
        column.settings_all_iterations.find_index { |i| i["id"] == value }
      elsif column&.single_select?
        column.settings_options.find_index { |o| o["id"] == value }
      else # null columns will also fall into this bucket
        title
      end
    end

    def ==(other)
      [view_id, column_id, value] == [other.view_id, other.column_id, other.value]
    end
    alias_method :eql?, :==

    def <=>(other)
      if data_type != other.data_type
        raise ArgumentError, "cannot compare: #{column.data_type} with #{other.data_type}"
      end

      # this will ensure we have 2 non-null values to compare against.  In the case one is null then
      # ensure we do not compare them with the null and instead return back ordering so nulls are on the bottom
      # for ascending and top for descending.
      if sort_value.present? && other.sort_value.present?
        sort_value <=> other.sort_value
      elsif sort_value.present?
        -1
      else
        1
      end
    end

    def column_id
      column&.synthetic_id
    end
  end
end
