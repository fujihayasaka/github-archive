# typed: false
# frozen_string_literal: true

# Patches (right now just one, and we should try to keep it that way) for
# the Addressable library. The only patch at the moment updates
# `Addressable::URI.parse` to prohibit percent-encoded NULs.
module AddressableMonkeyPatches
  # The string we want to prohibit.  This is the percent-encoded form of
  # `NUL`, i.e. \u0000.  There's no non-malicious reason it should ever
  # be in a URI being parsed in production at github, so in order to
  # harmonize the differences between Addressable::IDNA::Pure and
  # Addressable::IDNA::Native that are making it difficult to merge
  # github/github#170248, we decided to forbid it entirely using a
  # monkeypatch as the first step of the process.
  #
  # See RFC 3986 for a justification for why banning this string from
  # incoming URIs is permissable behavior for a conforming URI-handling
  # application such as GitHub:
  #
  #  > Note, however, that the "%00" percent-encoding (NUL) may
  #  > require special handling and should be rejected if the
  #  > application is not expecting to receive raw data within a
  #  > component.
  #
  PERCENT_ENCODED_NUL = "%00"

  # The module containing the monkeypatch itself which will be
  # prepended into the ancestor chain of the target (normally the
  # `Addressable::URI` class)
  module Patch
    def parse(uri)
      if uri.to_s.include?(::AddressableMonkeyPatches::PERCENT_ENCODED_NUL)
        raise(
          ::AddressableMonkeyPatches::NulNotAllowed,
          "#{uri.inspect} contains `%00`. Please adjust the `parse` callsite to rescue `Addressable::URI::InvalidURIError` and reject the URI"
        )
      end
      super
    end
  end

  # Raised at runtime by our patched `parse` implementation when a NUL is
  # encountered.  We should rescue this exception at appropriate callsites
  # and reject the incoming URI instead of raising.
  # We inherit from InvalidURIError since that is already raised by
  # Addressable when parsing some garbage URIs (and rescued appropriately)
  # so we can piggyback onto that existing rescue.
  class NulNotAllowed < ::Addressable::URI::InvalidURIError
  end

  # Raised by our `patch!` method if the target class we are attempting to
  # patch is not acceptable (e.g. lacks a `parse` method or has one with
  # incompatible arity).
  class BadTarget < ArgumentError
  end


  # Tracks already patched classes to prevent double-patching.
  @patched = {}

  # Patch a class that looks a lot like Addressable::URI, namely
  # that it has a `parse` class method with arity == 1.
  # After patching, the target's `parse` class method will execute
  # the above `NUL` check before running its usual implementation.
  def self.patch!(target: Addressable::URI)
    validate_acceptable_target(target)

    target.singleton_class.prepend(::AddressableMonkeyPatches::Patch)
    @patched[target] = true
  end

  # Make extra super sure that we're patching the right class.
  private_class_method def self.validate_acceptable_target(target)
    raise(BadTarget, "#{target.inspect} already patched") if @patched[target]

    unless target.respond_to?(:parse)
      raise(BadTarget, "#{target.inspect} has no `parse` method to patch")
    end
    unless target.method(:parse).arity == 1
      raise(BadTarget, "#{target.inspect} has a `parse` method but is not unary")
    end
  end
end
