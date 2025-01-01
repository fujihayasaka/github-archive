# typed: true
# frozen_string_literal: true

class GitHub::Diff::Line
  # Type of line. One of :hunk, :context, :addition, :deletion, :nonewline, or :empty.
  attr_reader :type

  # Raw diff line text with prefix characters.
  attr_reader :text

  # The zero-based line offset into the raw diff text for this set of changes.
  attr_reader :position

  # Integer line offset into the file on the left side of the diff
  attr_reader :left

  # Integer line offset into the file on the right side of the diff
  attr_reader :right

  # Either left or right, depending on the type of line.
  attr_reader :current

  # Boolean flag if line is not followed by a line break
  attr_accessor :nonewline
  alias_method :nonewline?, :nonewline

  # A "related" GitHub::Diff::Line object, or nil.
  #
  # "Related" lines are pairs of deleted/added lines that are determined to be
  # "the same line" (modulo any modifications to the line). For example, if the
  # entire diff consists of a change to a single character in the file, the
  # deleted/added versions of that line are considered to be "related". This is
  # useful, e.g., for highlighting changes to words within lines.
  attr_accessor :related_line

  # MRI always allocates a Hash when passing keyword arguments to
  # .new/#initialize. Thousands of GitHub::Diff::Line objects can be created in
  # a single request so these Hashes add up. We avoid the Hash allocation by
  # defining our own .new method rather than using the built-in one, and only
  # passing positional arguments to the built-in .new.
  def self.new(type:, text:, position: nil, left: nil, right: nil, current: nil, nonewline: false)
    super(type, text, position, left, right, current, nonewline)
  end

  def initialize(type, text, position, left, right, current, nonewline)
    @type = type
    @text = text
    @position = position
    @left = left
    @right = right
    @current = current
    @nonewline = nonewline
  end

  def to_a
    ary = [type, position, left, right, current, related_line ? related_line.position : nil, text]
    ary << :nonewline if nonewline?
    ary
  end

  # Exclude `@related_line` ivar from the default activesupport-supplied JSON
  # serialization behavior to prevent infinite mutual recursion between a pair
  # of related lines.
  def instance_values
    super.except("related_line")
  end

  def deletion?
    type == :deletion
  end

  def addition?
    type == :addition
  end

  def hunk?
    type == :hunk
  end

  def context?
    type == :context || type == :injected_context
  end

  # If this method returns true, this is a context line that is not in close
  # proximity of an actual change. It was *injected* by passing
  # :context_lines when constructing a GitHub::Diff instance.
  def injected_context?
    type == :injected_context
  end

  def no_newline?
    type == :nonewline
  end

  # Using left and right would result in the blob position being off by one. For example, the first line would
  # be line 1 of the blob instead of line 0 whereas the first line of the diff is position 0.
  def blob_left
    left.nil? ? nil : left - 1
  end

  def blob_right
    right.nil? ? nil : right - 1
  end

  EMPTY = GitHub::Diff::Line.new(type: :empty, text: nil, position: nil, left: nil, right: nil, current: nil)
end
