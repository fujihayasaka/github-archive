module Versioning
  class NamedVersion < Version

    # A NamedVersion is a type of version utilized in an ecosystem's package
    # release/dependency that points to a particular location in git history,
    # whether it is a commit sha, release tag, or branch name. Despite the quirk
    # of them being non-numerical, they are expected to act similarly to the
    # standard semantic version, in order to avoid breaking too much logic in
    # our application.

    # At the time of this writing only Actions supports this version type (as
    # well as semantic versions).

    attr_reader :name

    def initialize(name:)
      @name = name
    end

    def primary_identifier
      name
    end

    def to_s
      "#{name}"
    end

    def ==(other)
      return false unless other.is_a?(NamedVersion)

      name == other.name
    end

    def <=>(other)
      # use alphabetical ordering for comparing to another named version
      return name <=> other.name if other.is_a?(NamedVersion)

      super
    end

    def encoded
      InvalidEncodedVersion.new(name)
    end
  end
end
