# typed: false
# frozen_string_literal: true

module GitHub
  # Use a bigint column to store a timezone-neutral datetime.
  #
  # Usage:
  #
  #   class MyModel < ApplicationRecord::Mysql1
  #     include GitHub::UtcTimestamp
  #     utc_timestamp :expires_at # reads and writes to a "expires_at_timestamp" column.
  #   end
  module UtcTimestamp
    def self.included(base) #:nodoc:
      base.extend(ClassMethods)
    end

    module ClassMethods
      def utc_timestamp(*fields)
        fields.each do |field|
          self.class_eval <<-RUBY, __FILE__, __LINE__
            def #{field}
              if ts = read_attribute(#{field.inspect}_timestamp)
                Time.at(ts).utc
              end
            end

            def #{field}=(value)
              if value
                write_attribute(#{field.inspect}_timestamp, value.to_i)
              else
                write_attribute(#{field.inspect}_timestamp, nil)
              end
            end
          RUBY
        end
      end
    end
  end
end
