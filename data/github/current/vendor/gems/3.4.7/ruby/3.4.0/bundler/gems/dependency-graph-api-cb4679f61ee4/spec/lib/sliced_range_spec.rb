require "spec_helper"
require File.expand_path("../../../lib/sliced_range", __FILE__)

describe SlicedRange do
  it "returns contiguous ranges" do
    range = described_class.new(
      min:  0,
      max:  9,
      size: 5,
    )

    expect(range.subranges.to_a).to eq [
      (0..4),
      (5..9)
    ]
  end

  it "returns the remainder when the range doesn't evenly divide by the size" do
    range = described_class.new(
      min:  0,
      max:  10,
      size: 5,
    )

    expect(range.subranges.to_a).to eq [
      (0..4),
      (5..9),
      (10..10),
    ]

    range = described_class.new(
      min:  0,
      max:  11,
      size: 5,
    )

    expect(range.subranges.to_a).to eq [
      (0..4),
      (5..9),
      (10..11),
    ]
  end
end
