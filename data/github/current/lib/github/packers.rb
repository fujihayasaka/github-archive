# typed: true
# frozen_string_literal: true
require "msgpack"

module GitHub
  class ZlibPacker
    def initialize(packer, encoder = :encode, decoder = :decode)
      @encoder = packer.method(encoder)
      @decoder = packer.method(decoder)
    end

    def encode(object)
      return if object.blank?
      encoded = @encoder.call(object)
      Zlib::Deflate.deflate(encoded)
    end

    def decode(deflated)
      return {} unless deflated && !deflated.empty?
      encoded = Zlib::Inflate.inflate(deflated)
      @decoder.call(encoded)
    end
  end

  # Encodes and decodes data as gzipped message pack.
  ZPack = ZlibPacker.new(MessagePack, :pack, :unpack)

  # Encodes and decodes data as gzipped json.
  module ZSON
    def self.encode(body)
      return nil if body.blank?
      s = StringIO.new "".b
      z = Zlib::GzipWriter.new(s)
      z.mtime = 1386109546 # needed for stable result over multiple passes
      z.write GitHub::JSON.encode(body)
      z.close
      s.string
    end

    def self.decode(body)
      return {} if body.to_s.empty?
      s = StringIO.new(body)
      z = Zlib::GzipReader.new(s)
      hash = GitHub::JSON.decode(z.read)
      z.close
      hash
    end
  end
end
