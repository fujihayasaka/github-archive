class SlicedRange
  def initialize(min:, max:, size:)
    @min  = min
    @max  = max
    @size = size
  end

  def each(&block)
    subranges.each(&block)
  end

  def subranges
    range
      .step(@size)
      .map { |i| Range.new(i, [i + @size - 1, @max].min) }
  end

  private

  def range
    Range.new(@min, @max)
  end
end
