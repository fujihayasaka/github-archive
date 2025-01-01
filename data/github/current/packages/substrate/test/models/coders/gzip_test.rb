# typed: true
# frozen_string_literal: true

require "test_helper"

class CodersGzipTest < GitHub::TestCase
  setup do
    # first block is header, second is mtime, third is mostly data and crc
    @gzipped_hi = ["1f8b0800" + "89c9f15c00" + "03cbc80400ac2a93d802000000"].pack("H*")
  end

  test "#dump zips the data" do
    zipped = Coders::Gzip.new.dump("hi")
    # ignore bytes 4-8 which contain mtime
    assert zipped.start_with? @gzipped_hi.byteslice(0..3)
    assert zipped.end_with? @gzipped_hi.byteslice(9..21)
  end

  test "#load unzips the data" do
    assert_equal "hi", Coders::Gzip.new.load(@gzipped_hi)
  end
end
