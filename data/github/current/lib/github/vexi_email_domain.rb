# typed: strict
# frozen_string_literal: true

# Custom Vexi actor representing an email domain.
# vexi_id is "VexiEmailDomain:{domain}" (short class name, not fully-qualified).
#
# Endswith semantics: for a user with email "attacker@z3qfs.gjrnj.cn", dotcom constructs
# actors for every suffix — VexiEmailDomain.new("z3qfs.gjrnj.cn"), VexiEmailDomain.new("gjrnj.cn") —
# and checks each against the flag. If any matches an actor ID in the flag, the user is
# blocked. A single DevPortal entry of "VexiEmailDomain:gjrnj.cn" therefore blocks
# @gjrnj.cn and @*.gjrnj.cn without enumerating subdomains.
module GitHub
  class VexiEmailDomain
    include GitHub::VexiActor

    sig { params(id: String).returns(VexiEmailDomain) }
    def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
      new(id)
    end

    # Returns actors for a user's email domain with endswith semantics.
    # For "user@a.b.gjrnj.cn": [VexiEmailDomain("a.b.gjrnj.cn"), VexiEmailDomain("b.gjrnj.cn"), VexiEmailDomain("gjrnj.cn"), VexiEmailDomain("cn")]
    # For "user@gjrnj.cn":     [VexiEmailDomain("gjrnj.cn"), VexiEmailDomain("cn")]
    # Returns [] if the email is blank or has no domain part.
    sig { params(email: String).returns(T::Array[VexiEmailDomain]) }
    def self.actors_for_email(email)
      return [] unless email.include?("@")

      domain = email.split("@").last.to_s.downcase.strip
      return [] if domain.empty?

      parts = domain.split(".")
      actors = []
      while parts.length > 0
        actors << new(parts.join("."))
        parts = parts.drop(1)
      end
      actors
    end

    sig { params(id: String).void }
    def initialize(id)
      @id = T.let(id.downcase.strip, String)
    end

    sig { returns(String) }
    def id
      @id
    end

    sig { returns(String) }
    def vexi_id
      "VexiEmailDomain:#{@id}"
    end

    sig { params(other: T.untyped).returns(T::Boolean) }
    def ==(other)
      other.is_a?(VexiEmailDomain) ? vexi_id == other.vexi_id : false
    end
    alias_method :eql?, :==
  end
end
