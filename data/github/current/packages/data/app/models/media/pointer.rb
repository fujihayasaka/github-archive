# typed: true
# frozen_string_literal: true

# A parsed representation of a Git LFS blob pointer.  Comes in two flavors:
#
# Old school:
#
#   # external
#   {oid}
#
# Current:
#
#   version https://git-lfs.github.com/spec/v1
#   [ext-{n}-{name} sha256:{oid} ...]
#   oid sha256:{oid}
#   size {size-in-bytes}
#
class Media::Pointer
  attr_accessor :version, :oid, :oid_type, :size, :exts

  SIZE_LIMIT = 1024 # Max size of a blob pointer
  ALPHA_VERSION = "http://git-media.io/v/1"
  ALPHA_OID_TYPE = "sha256"

  VERSIONS = {
    "https://git-lfs.github.com/spec/v1" => {
      "oid" => lambda { |p, v|
        oid_type, oid = v&.split(":", 2)
        return unless oid_type == "sha256"
        return unless oid.match(/\A[0-9a-f]{64}\z/)
        p.oid_type = oid_type
        p.oid = oid
      },
      "size" => lambda { |p, v|
        return unless v&.match(/\A\+?[0-9]+\s*\z/)
        p.size = v.to_i
      },
      :keys => %w(oid size),
    },
  }

  # backwards compatible with beta objects
  VERSIONS["https://hawser.github.com/spec/v1"] = VERSIONS["https://git-lfs.github.com/spec/v1"]
  VERSIONS["http://git-media.io/v/2"] = VERSIONS["https://git-lfs.github.com/spec/v1"]

  def initialize(version = nil, oid = nil, oid_type = nil, size = nil, exts = nil)
    @version = version
    @oid = oid
    @oid_type = oid_type
    @size = size
    @exts = exts
  end

  class Extension
    attr_accessor :name, :oid, :oid_type

    def initialize(name = nil, oid = nil, oid_type = nil)
      @name = name
      @oid = oid
      @oid_type = oid_type
    end
  end

  def self.parse(data)
    return if data.nil? || data.size > SIZE_LIMIT

    parse_lines(clean_encoding(data).split(/\n/u))
  end

  def self.parse_lines(lines)
    lines.reject! { |line| line.empty? }

    key = "lfs.parse_pointer"
    case lines[0]
    when /git-lfs/u
      GitHub.dogstats.increment(key, tags: %w(version:git-lfs))
      parse_versioned(lines)
    when /\A# .*git-media/u
      GitHub.dogstats.increment(key, tags: %w(version:legacy-git-media))
      new(ALPHA_VERSION, lines.last, ALPHA_OID_TYPE, 0)
    when /\A# .*|external/u
      GitHub.dogstats.increment(key, tags: %w(version:legacy-external))
      nil
    when /hawser/u
      GitHub.dogstats.increment(key, tags: %w(version:hawser))
      parse_versioned(lines)
    when /git-media/u
      GitHub.dogstats.increment(key, tags: %w(version:git-media))
      parse_versioned(lines)
    end
  end

  def self.parse_versioned(lines)
    key, version = lines.shift.split(/ /, 2)

    # Note that the Git LFS client allows extension entries before the
    # version line, but this is likely an oversight which will be corrected
    # a future Git LFS client release.
    return unless key == "version"
    return unless parser = VERSIONS[version]

    pointer = new(version)

    keys = parser[:keys].dup
    key = keys.shift
    while line = lines.shift
      k, v = line.split(/ /, 2)
      if k == key
        return if parser[k].call(pointer, v).nil?

        key = keys.shift
        break if key.nil?
      else
        # Note that the Git LFS client permits arbitrary non-whitespace
        # characters following the extension name because its regular
        # expression lacks a final \z, but this is likely an oversight
        # which will be corrected in a future Git LFS client release.
        return unless match = k.match(/\Aext-(\d{1})-(\w+)/)

        n = match.captures[0].to_i
        ext = Extension.new(match.captures[1])
        return if parser["oid"].call(ext, v).nil?

        if pointer.exts.nil?
          pointer.exts = []
        else
          return unless pointer.exts[n].nil?
        end

        pointer.exts[n] = ext
      end
    end

    return unless key.nil?
    return unless lines.reject { |line| line.blank? }.empty?

    pointer
  end

  DIFF_OPERATIONS = {
    " " => lambda { |line, o, n| o << line; n << line },
    "-" => lambda { |line, o, _n| o << line },
    "+" => lambda { |line, _o, n| n << line },
  }

  # Parses a diff into two Media::Blob pointers.
  #
  #  @@ -1,3 +1,3 @@
  #   version http://git-media.io/v/2
  #  -oid sha256:3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea
  #  -size 6294357
  #  +oid sha256:01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0
  #  +size 6308114
  #
  # Returns an Array of two elements, which are each either nil or
  # Media::Pointer objects, or an empty Array.
  def self.parse_diff(diff)
    text = diff.try(:text) || diff.to_s
    return [] if text.size > (SIZE_LIMIT * 2) || text.blank?
    lines = clean_encoding(text.dup).split("\n")
    lines.shift # first line has the @@ diff meta stuff
    old_data = []
    new_data = []

    lines.each do |line|
      next unless op = DIFF_OPERATIONS[line[0]]
      op.call(line[1..-1], old_data, new_data)
    end

    [parse_lines(old_data), parse_lines(new_data)]
  end

  def self.clean_encoding(data)
    if data.encoding != Encoding::UTF_8
      data.encode!(
        Encoding::UTF_8,
        invalid: :replace,
        undef: :replace,
        replace: "?",
      )
    end

    data
  end
  private_class_method :clean_encoding
end
