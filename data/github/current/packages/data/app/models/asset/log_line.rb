# typed: true
# frozen_string_literal: true

# Adapted from AWS-S3 gem
# https://github.com/github/aws-s3/blob/master/lib/aws/s3/logging.rb
# https://github.com/github/aws-s3/blob/master/lib/aws/s3/extensions.rb
class Asset::LogLine

  DATE          = /\[([^\]]+)\]/
  QUOTED_STRING = /"([^"]+)"/
  REST          = /(\S+)/
  EMPTY_VALUE   = "-".freeze
  LINE_SCANNER  = /#{DATE}|#{QUOTED_STRING}|#{REST}/

  # Lame hack since Date._parse is so accepting. S3 dates are of the form:
  # '2006-10-29T23:14:47.000Z'. So unless the string looks like that, don't even
  # try, otherwise it might convert an object's key from something like
  # '03 1-2-3-Apple-Tree.mp3' to Sat Feb 03 00:00:00 CST 2001.
  DATE_FORMAT   = /\A\d{4}-\d{2}-\d{2}\w\d{2}:\d{2}:\d{2}/
  INT_FORMAT    = /\A[1-9]+\d*\z/
  TRUE          = "true".freeze
  FALSE         = "false".freeze

  cattr_accessor :decorators
  @@decorators = Hash.new { |hash, key| hash[key] = lambda { |entry| Asset::LogLine.coerce(entry) } }
  cattr_reader   :fields
  @@fields     = []

  def self.field(name, offset, &block)
    decorators[name] = block if block_given?
    fields << name
    class_eval(<<-EVAL, __FILE__, __LINE__)
      def #{name}
        return @__#{name} if defined?(@__#{name})
        value = @parts[#{offset} - 1]
        @__#{name} = if value == EMPTY_VALUE
          nil
        else
          self.class.decorators[:#{name}].call(value)
        end
      end
    EVAL
  end

  # Time.parse doesn't like %d/%B/%Y:%H:%M:%S %z so we have to transform it unfortunately
  def self.typecast_time(datetime) #:nodoc:
    datetime.sub!(%r|\A(\w{2})/(\w{3})/(\w{4})|, '\2 \1 \3')
    datetime.sub!(":", " ")
    Time.parse(datetime)
  end

  def self.coerce(str)
    case str
    when TRUE  then true
    when FALSE then false

    # Don't coerce numbers that start with zero
    when INT_FORMAT  then Integer(str)
    when DATE_FORMAT then Time.parse(str)
    else str
    end
  end

  def initialize(line) #:nodoc:
    @line = line
    @parts = line.scan(LINE_SCANNER).flatten.compact
  end

  def to_s
    @line
  end

  field :owner,            1
  field :bucket,           2
  field(:time,             3) { |entry| typecast_time(entry) }
  field :remote_ip,        4
  field :requestor,        5
  field :request_id,       6
  field :operation,        7
  field :key,              8
  field :request_uri,      9
  field :http_status,      10
  field :error_code,       11
  field :bytes_sent,       12
  field :object_size,      13
  field :total_time,       14
  field :turn_around_time, 15
  field :referrer,         16
  field :user_agent,       17

  attr_reader :parts
end
