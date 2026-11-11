# frozen_string_literal: true

module GzipHelpers
  def gzip(data)
    io = StringIO.new
    writer = Zlib::GzipWriter.new(io)
    writer.write(data)
    writer.close
    io.string
  end
end
