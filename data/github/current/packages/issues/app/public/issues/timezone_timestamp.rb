# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Issues
  module TimezoneTimestamp
    def self.included(base) #:nodoc:
      base.extend(ClassMethods)
    end

    module ClassMethods
      extend T::Helpers

      requires_ancestor { Kernel }

      # A class macro for defining timestamp attribute readers and writers.
      # Such attributes are exposed as a single Time object, but stored in the
      # database as two values. First, the timestamp's integer value `{field}_timestamp}`
      # representing the number of seconds since the Epoch. Second, the
      # timestamp's UTC offset `{field}_offset` as the number of seconds between
      # the timezone of time and UTC.
      def timezone_timestamp(*fields)
        fields.each do |field|
          self.class_eval <<-RUBY, __FILE__, __LINE__
            def #{field}
              if ts = read_attribute(#{field.inspect}_timestamp)
                Time.at(ts).localtime(read_attribute(#{field.inspect}_offset))
              end
            end

            def #{field}=(value)
              if value
                write_attribute(#{field.inspect}_timestamp, value.to_i)
                write_attribute(#{field.inspect}_offset, value.utc_offset)
              else
                write_attribute(#{field.inspect}_timestamp, nil)
                write_attribute(#{field.inspect}_offset, nil)
              end
            end
          RUBY
        end
      end
    end
  end
end
