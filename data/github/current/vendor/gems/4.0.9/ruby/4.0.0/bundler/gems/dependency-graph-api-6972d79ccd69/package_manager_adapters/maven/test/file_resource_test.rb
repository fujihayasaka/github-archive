require "test_helper"

class FileResourceTest < Minitest::Test
  def setup
    FileUtils.mkdir_p("maven_data/")
    @filename = "maven_data/foo.txt"

    File.open(@filename, "w") do |f|
      f.write "something"
    end
  end

  def teardown
    File.delete(@filename)
  end

  def test_read_write_file
    file = Maven::FileResource::ReadWriteFile.new(@filename)
    assert_equal "something", file.read.to_io.read

    ruby_io = file.write.to_io
    ruby_io.write("foobar")
    ruby_io.close
    file.close

    file = File.open(@filename, "r")
    assert_equal "foobar", file.read
  end
end
