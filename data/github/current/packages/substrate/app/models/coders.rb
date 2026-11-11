# typed: true
# frozen_string_literal: true

require "lz4-ruby"

module Coders
  module_function

  def compose(*coders, default: nil, errors: [], &handler)
    Default.new(RescueErrors.new(Composed.new(coders), errors, &handler), default)
  end

  def wrap(target, dump: :encode, load: :decode)
    build dump: target.method(dump), load: target.method(load)
  end

  def build(dump:, load:)
    Object.new.tap do |coder|
      coder.define_singleton_method :dump, &dump
      coder.define_singleton_method :load, &load
    end
  end

  LZ4 = wrap(::LZ4, dump: :compress, load: :uncompress)
  ZSTREAM = build(dump: Zlib::Deflate.method(:deflate), load: Zlib::Inflate.method(:inflate))
end
