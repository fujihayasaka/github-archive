# typed: true
# frozen_string_literal: true

# In the following formatters, we go through these steps:
# * dup because #utc modifies the receiver
# * utc to get UTC representation
# * to_time to ensure we're dealing with a Time object
# * utc again to get pure utc representation of the time

Time::DATE_FORMATS[:db_utc] = lambda { |time|
  time.dup.utc.to_time.utc.strftime("%Y-%m-%d %H:%M:%S")
}

Time::DATE_FORMATS[:db] = lambda { |time|
  time = time.dup.utc.to_time.utc

  if !defined?(ActiveRecord.default_timezone) || ActiveRecord.default_timezone == :local
    # our DB is in local time (ugh), so make sure the time object is
    # converted to local time before converting it to a db string
    #
    # also we have to do this ridiculous dance to ensure that we can
    # turn any given DateTime object into something in localtime.
    time = time.getlocal
  end

  time.strftime("%Y-%m-%d %H:%M:%S")
}
