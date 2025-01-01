# typed: true
# frozen_string_literal: true

# adapted from: https://github.com/technoweenie/horcrux/blob/731a7f0556443ddefe8ea11302fb6a834548c68d/lib/horcrux/serializers/gzip_serializer.rb

module Coders
  class Gzip
    def dump(value)
      StringIO.open do |s|
        Zlib::GzipWriter.wrap(s) do |z|
          z.write value
        end
        s.string.b
      end
    end

    def load(value)
      Zlib::GzipReader.wrap(StringIO.new(value), &:read)
    end
  end
end
