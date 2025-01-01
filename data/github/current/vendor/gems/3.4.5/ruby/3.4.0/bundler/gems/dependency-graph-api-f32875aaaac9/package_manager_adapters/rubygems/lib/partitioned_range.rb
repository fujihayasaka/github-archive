class PartitionedRange
  def initialize(min:, max:, partitions:)
    @min        = min.to_i
    @max        = max.to_i
    @partitions = partitions.to_i
  end

  def each(&block)
    subranges.each(&block)
  end

  def map(&block)
    subranges.map(&block)
  end

  private

  def subranges
    return [range] unless range.size > partitions

    range
      .step(step_size)
      .to_a
      .tap(&:pop)
      .push(max + 1)
      .each_cons(2)
      .map { |lower, upper| (lower...upper) }
  end

  attr_reader :min, :max, :partitions

  def step_size
    range.size / partitions
  end

  def range
    (min..max)
  end
end
