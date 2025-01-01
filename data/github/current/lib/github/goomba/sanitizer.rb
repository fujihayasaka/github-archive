# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  module Sanitizer
    # Constructs a Goomba::Sanitizer based on the given whitelist.
    #
    # whitelist - a Sanitize-style whitelist Hash
    #
    # Returns a Goomba::Sanitizer.
    #
    # TODO Please replace calls to this method with calls to from_allowlist,
    # updating test/fixtures/existing_allowed_denied_language_test_files.txt
    # where possible.
    #
    # When all calls have been migrated, copy this method's body into from_allowlist,
    # update it there to rename references to "whitelist" and delete this method.
    def self.from_whitelist(whitelist)
      whitelist = whitelist.dup
      # h7/h8 are in the default whitelist, but aren't standard HTML elements.
      # Goomba complains if we try to whitelist them. Hopefully no one's using
      # these in their content.
      whitelist[:elements] = whitelist.fetch(:elements, []) - %w[h7 h8]

      Goomba::Sanitizer.from_hash(whitelist)
    end

    # Constructs a Goomba::Sanitizer based on the given allowlist.
    #
    # allowlist - a Sanitize-style allowlist Hash
    #
    # Returns a Goomba::Sanitizer.
    def self.from_allowlist(allowlist)
      from_whitelist(allowlist)
    end
  end
end
