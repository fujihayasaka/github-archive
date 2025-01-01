# typed: false
# frozen_string_literal: true

require "active_support/core_ext/module/delegation"
require "active_support/core_ext/array/wrap"
require "active_support/core_ext/object/blank"

# An representation of the path to trees or blobs in a Repository.
#
# The goal of this class is to handle repository path information in a cleaner
# way than manipulating Arrays or Strings. It can be used in most places where
# an Array or String path is expected. It is immutable. All methods for
# altering the path return new RepositoryPath instances.
class RepositoryPath
  include Enumerable

  delegate :empty?, :last, :size, to: :segments
  # FIXME: remove these after refactoring
  delegate :flatten, to: :segments

  # parts - A String or Array of the path from the root of a repository
  def initialize(parts = [])
    @path = Array.wrap(parts).compact.join("/")
    @path.squeeze!("/")      # Remove successive slashes
    @path.gsub!(/\A\//, "")  # Remove leading slashes
    @path.freeze
  end

  # Appends the given pathnames onto self to create a new RepositoryPath
  #
  #     >> RepositoryPath.new('app/models').append('repository.rb').to_s
  #     => "app/models/repository.rb"
  #
  # path - A String or Array of path segments to append
  #
  # Returns a new RepositoryPath
  def append(*path)
    RepositoryPath.new(segments + path)
  end

  # Get the parent of this path
  #
  #     >> RepositoryPath.new('app/models').parent.to_s
  #     => "app"
  #
  # Returns a new RepositoryPath
  def parent
    RepositoryPath.new(segments.slice(0...-1))
  end

  # Each of the path segments
  #
  # Returns an Array of strings
  def segments
    @path.split("/")
  end

  # Iterate over the segments of the path.
  def each(&block)
    segments.each(&block)
  end

  # Compare this path to another.
  #
  #     RepositoryPath.new(['app', 'models']) == "app/models"
  #
  # other - Another RepositoryPath or String
  #
  # Returns true if the paths are equal, false otherwise
  def ==(other)
    @path == other.to_s
  end

  # Convert this path to a String by joining the path segments with a "/"
  def to_s
    @path.dup
  end
  alias :to_str :to_s

  # Convert this path to a scrubbed Unicode String
  def for_display
    string = to_s
    if string.encoding == ::Encoding::UTF_8 && string.valid_encoding?
      string
    else
      string.force_encoding(::Encoding::UTF_8).scrub!
    end
  end

  # Iterates over and yields a new path object for each segment in the path
  #
  #     >> RepositoryPath.new('app/models').descend.map(&:to_s)
  #     => ['', 'app', 'app/models']
  #
  # block - An optional block. If missing, an Enumerator will be returned
  def descend(&block)
    return enum_for(:descend) unless block

    path = RepositoryPath.new
    block.call path
    each do |segment|
      path = path.append(segment)
      block.call path
    end
    self
  end
end
