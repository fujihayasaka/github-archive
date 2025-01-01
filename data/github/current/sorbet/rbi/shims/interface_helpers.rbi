# typed: strict
# frozen_string_literal: true

module PlatformTestHelpers::InterfaceHelpers
  def self.assert_equal(expected, actual, msg = T.unsafe(nil)); end

  sig { params(name: String, opts: T::Hash[Symbol, T.untyped], block: T.proc.void).void }
  def self.test(name, opts = {}, &block); end

  sig { returns(T::Boolean) }
  def self.skip; end
end
