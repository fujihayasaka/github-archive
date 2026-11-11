# typed: true
# frozen_string_literal: true

# Custom attribute type for UTC datetime columns
# Must be configured for all UTC datetime columns in newsies
#
# class MyModel < ApplicationRecord::Domain::Notifications
#   attribute :created_at, ApplicationRecord::UTCTimeType.new
# end
#
# For historical reasons, all datetime columns in the newsies
# database store times as UTC. However, mysql1 stores datetimes
# as PST (as configured with ActiveRecord.default_timezone)
#
# There is no way to configure ActiveRecord to use a different
# timezone per table/database, so instead this custom type ensures
# we do the conversion correctly for UTC columns
#
# Using this type should fix all your woes with one exception, queries
# like this `model.where("created_at > ?", Time.now)` will not work
# correctly.
module ApplicationRecord
  class UTCTimeType < ::ActiveModel::Type::DateTime
    # MySQL date format
    DATE_FORMAT = "%Y-%m-%d %H:%M:%S"

    def type
      :utc_time
    end

    # When we pull dates from the database, the connection adapter will
    # have parsed them in local time, like this:
    #
    # "2018-12-11 09:15:30" -> `2018-12-11 09:15:30 -0800`
    #
    # We know this is wrong for UTC tables. Since we can't get at the
    # actual string stored in the DB, we need to correct it back by the UTC
    # offset.
    def deserialize(value)
      case value
      when ::Time
        # Correct by the utc_offset, and force tz to be utc
        (value + value.utc_offset).utc
      else
        value
      end
    end

    # On the way into the database, we need to cast to a string really early
    # Otherwise activerecord will take over and convert it into a local timezone
    def serialize(value)
      if value.acts_like?(:time)
        value = value.utc.strftime(DATE_FORMAT)
      end

      value
    end

    # This ensure we get the right value for schema dumps
    def type_cast_for_schema(value)
      serialize(value)
    end
  end
end
