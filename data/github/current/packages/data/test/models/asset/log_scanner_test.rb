# typed: true
# frozen_string_literal: true

require "test_helper"

class AssetLogScannerTest < GitHub::TestCase

  setup do
    @object = FakeObject.new("line", chunk_size: 1024)
    @client = FakeClient.new(@object)
    @scanner = Asset::LogScanner.new(@client, "bucket", "prefix")
    @logset = Asset::LogScanner::LogSet.new(@scanner, [], false)

    @log_line_template = %Q(a92 github-cloud [18/Feb/2020:20:10:19 +0000] %s arn:aws:iam::895557238572:user/git-media 78F1ABD94F146A7E REST.GET.OBJECT alambic/media/... "GET /alambic/media/... HTTP/1.1" 200 - 16352 16352 10 9 "-" "git-lfs/2.5.1" - bvE0= SigV4 ECDHE-RSA-AES128-GCM-SHA256 QueryString github-cloud.s3.amazonaws.com TLSv1.2)
  end

  [4, 6, 7, 10, 100].each do |chunk_size|
    test "stream log body into s3 lines using chunk_size #{chunk_size}" do
      o = FakeObject.new("line 1\nline 2\nline 3", chunk_size: chunk_size)
      c = FakeClient.new(o)

      scanner = Asset::LogScanner.new(c, "bucket", "prefix")
      scanner.minimum_log_parts = 0 # parsing fake lines

      lines = []
      logset = Asset::LogScanner::LogSet.new(scanner, [], false)
      logset.each_line(o) do |line|
        lines << line
      end

      assert_equal ["line 1", "line 2", "line 3"], lines.map(&:to_s)
      assert_equal [Asset::LogLine], lines.map(&:class).uniq
    end
  end

  ["192.0.2.82", "2001:db8::3", "[2001:db8::3]"].each do |ip_address|
    test "filters IP address from S3 log line using address #{ip_address}" do
      Failbot.expects(:report).with do |err, context|
        assert_kind_of ArgumentError, err
        refute context[:s3_log_line][ip_address], "'#{context[:s3_log_line]}' includes '#{ip_address}'"
        assert_equal format(@log_line_template, "IP-ADDRESS"), context[:s3_log_line]
      end

      err = ArgumentError.new
      raw_line = format(@log_line_template, ip_address)
      @logset.log_error(err, s3_log_line: raw_line)

      Failbot.unstub(:report)
    end
  end

  class FakeClient
    def initialize(*objects)
      @objects = objects
    end

    def get_object(bucket:, key:, &block)
      obj = @objects.detect do |o|
        o.bucket_name == bucket && o.key == key
      end

      if !obj
        raise "No object for #{bucket}/#{key}"
      end

      obj.get(&block)
      obj
    end
  end

  # Implements the Aws::S3::Object#get behavior with a block arg that
  # #each_line depends on. The given chunk size is used to test scenarios where
  # chunks are from the middle of a line, the end of a line, or contain multiple
  # lines.
  class FakeObject
    attr_reader :key
    attr_reader :body

    def initialize(body, chunk_size:)
      @body = body
      @chunk_size = chunk_size
      @key = Time.now.utc.strftime("s3/%Y-%m-%d-%H-%M-00-#{SecureRandom.hex(16)}")
    end

    def bucket_name
      "bucket"
    end

    def get(&block)
      block.call ""
      @body.chars.in_groups_of(@chunk_size) do |group|
        block.call group.compact.join
      end
    end
  end
end
