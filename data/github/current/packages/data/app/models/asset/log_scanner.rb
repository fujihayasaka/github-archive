# typed: true
# frozen_string_literal: true

class Asset::LogScanner
  LOG_KEY_TIME_FORMAT = "%Y-%m-%d-%H-%M-%S"
  IP_ADDRESS_MATCH = /(\s+)(?:(?:\d+\.){3}\d+|\[?(?:[a-f0-9]+:(?:[a-f0-9]*:)+[a-f0-9]*)\]?)(\s+)/
  TIME_OFFSET = 1.hour

  attr_reader :client
  attr_reader :bucket
  attr_reader :log_key_prefix
  attr_accessor :time_offset
  attr_accessor :max_keys
  attr_accessor :object_key_matcher
  attr_accessor :minimum_log_parts

  def initialize(client, bucket, log_key_prefix, max_keys: 300)
    @bucket = bucket
    @log_key_prefix = log_key_prefix
    @time_offset = TIME_OFFSET
    @max_keys = max_keys
    @object_key_matcher = nil
    @minimum_log_parts = 0
    @client = client
  end

  # Finds the next logs to scan based on the marker and this scanner's
  # properties. Does not read the log data until #each is called.
  def find(marker)
    # NOTE: AWS never actually returns logs earlier than the marker.
    earliest = marker_to_time(marker) - @time_offset

    begin
      logs = @client.list_objects(
        bucket: @bucket,
        marker: marker,
        max_keys: @max_keys,
        prefix: @log_key_prefix,
      )
    rescue Aws::Errors::ServiceError => err
      GitHub.dogstats.increment("s3_usage.aws_error")
      Failbot.report(err, marker: marker)
      # By re-raising the error here we ensure the calling job will schedule
      # itself to retry and thus make another request using the same marker.
      # Note that the AWS SDK will have already retried this request as well.
      raise err
    end

    is_truncated = logs.is_truncated
    log_files = logs.contents.delete_if do |log|
      if log.key =~ /\A#{@log_key_prefix}\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2}-[A-Z0-9]+\z/ && marker_to_time(log.key) < earliest

        GitHub.dogstats.increment("s3_usage.early_log")
      end
      log.key !~ /\A#{@log_key_prefix}\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2}-[A-Z0-9]+\z/ ||
        marker_to_time(log.key) < earliest
    end

    LogSet.new(self, log_files.map { |log_file| log_file.key }, is_truncated)
  end

  # log_key_prefix: "s3/"
  # s3/2015-01-27-01-32-29-A0A382B60FE63B4D
  def marker_to_time(key)
    parts = key.to_s[@log_key_prefix.size..-1].split("-")
    Time.utc(*parts[0..5])
  end

  def time_to_marker(time)
    time.strftime("#{@log_key_prefix}#{LOG_KEY_TIME_FORMAT}")
  end

  def allows_object_key?(uri)
    return true unless @object_key_matcher
    uri =~ @object_key_matcher
  end

  # Represents a group of logs to parse. It is designed for a single parsing
  # attempt. Any errors will be reported to Failbot. Call LogScanner#find to
  # resume parsing logs in case of an error.
  class LogSet
    attr_reader :keys
    attr_reader :line_count
    attr_reader :scan_count
    attr_reader :scan_errors

    def initialize(scanner, keys, is_truncated = nil)
      @scanner = scanner
      @is_truncated = is_truncated
      @keys = keys.sort.freeze
      @line_count = 0
      @scan_count = 0
      @scan_errors = []
      @scanned = false
      @bucket = scanner.bucket
      @client = scanner.client
    end

    def truncated?
      !!@is_truncated
    end

    def scan_error?
      @scan_errors.any?
    end

    def size
      @keys.size
    end

    def each(&block)
      raise "already scanned logs" if @scanned
      @scanned = true

      @keys.each do |log_key|
        log = Aws::S3::Object.new(@bucket, log_key, client: @client)

        log_date = @scanner.marker_to_time(log_key)
        begin
          each_line(log) do |raw_line|
            begin
              next unless line = parse_raw_line(raw_line, log_date)
              block.call(log, line)
              @line_count += 1
            rescue ArgumentError, Rack::QueryParser::ParamsTooDeepError => err
              GitHub.dogstats.increment("s3_usage.log_line_error")
              log_error(err, s3_log_file: log_key, s3_log_line: raw_line.to_s)
            end
          end
        rescue Aws::Errors::ServiceError => err
          @scan_errors << err
          GitHub.dogstats.increment("s3_usage.aws_error")
          log_error(err, s3_log_file: log_key)
          # By returning here we ensure the previous log's key will be
          # recorded as the marker, so the next job run will start from
          # this log and try again to download it.  Note that the AWS SDK
          # will not have retried these requests to stream object data.
          return
        end
        @scan_count += 1
      end
    ensure
      @scan_errors.freeze
    end

    def log_error(err, context)
      context[:s3_log_line].gsub!(IP_ADDRESS_MATCH, '\1IP-ADDRESS\2') if context.key?(:s3_log_line)
      Failbot.report(err, context)
    end

    # Stream the object contents from a log file, and assemble raw log lines
    # from streaming data chunks.  The Aws::S3::Client#get_object() method
    # is described here:
    #
    #   https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html#get_object-instance_method
    #
    # The example for streaming data specifically notes:
    #
    #   WARNING: yielding data to a block disables retries of networking errors
    def each_line(log_object, &block)
      remainder = ""
      line_ending = "\n" # s3 logs use \n, regardless of $/
      log_path = "#{log_object.bucket_name}/#{log_object.key}"

      @client.get_object(bucket: log_object.bucket_name, key: log_object.key) do |chunk|
        next if chunk.blank?

        pieces = T.cast(chunk.split(line_ending), T::Array[String])
        next if pieces.size.zero?

        pieces[0] = remainder + T.must(pieces[0]) if remainder.size > 0
        if chunk.ends_with?(line_ending)
          remainder = ""
        else
          remainder = T.must(pieces.pop)
        end

        pieces.each do |p|
          build_log_line(block, p, log_path)
        end
      end

      build_log_line(block, remainder, log_path) if remainder.size > 0
    end

    def build_log_line(block, line, log_path)
      logline = Asset::LogLine.new(line)

      # Ensure the log has enough parts to process the entire log entry per
      # the Asset::LogLine class; this value is set by SyncAssetUsageParserJob.
      if @scanner.minimum_log_parts.to_i > 0 && logline.parts.size < @scanner.minimum_log_parts
        return
      end

      block.call(logline)
    end

    def parse_raw_line(line, log_date = nil)
      # Ignore this line if it has no request URI. This happens for S3 copying
      return if line.request_uri.nil?

      # ignore if it's a bad http status
      return if line.http_status.to_i > 299

      # Ignore this line if it happened 4 hours before the log time
      # or 4 hours after the log time.
      # NOTE: We likely want to ignore any lines which supposedly
      #       happened after the log time, should they ever occur.
      line_time = line.time.utc
      if log_date
        if line_time < log_date.utc - 4.hours
          GitHub.dogstats.increment("s3_usage.early_log_line")
          return
        elsif line_time > log_date.utc
          GitHub.dogstats.increment("s3_usage.late_log_line")
          return if line_time > log_date.utc + 4.hours
        end
      end

      method, uri = *line.request_uri.split(" ")

      return unless @scanner.allows_object_key?(uri)

      query_string = uri.split("?", 2)[1]
      query_params = query_string.blank? ? {} : Rack::Utils.parse_query(query_string)

      {
        request_id: line.request_id,
        time: line_time,
        hour_aligned_time: line_time.change(min: 0, sec: 0),
        method: method.upcase,
        uri: uri,
        query: query_params,
        raw: line,
      }
    rescue ArgumentError => err
      if err.to_s =~ /no time information/i
        return nil
      end
      raise
    end
  end
end
