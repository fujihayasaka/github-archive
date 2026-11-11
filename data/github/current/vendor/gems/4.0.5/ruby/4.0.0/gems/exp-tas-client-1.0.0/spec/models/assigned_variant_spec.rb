# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe ExpTasClient::AssignedVariant do
  let(:attrs) do
    {
      name: 'flight-1',
      numberline: 'nl1',
      is_forced: false,
      variant_allocation_id: 352
    }
  end

  subject { described_class.new(attrs) }

  it 'creates an instance with all attributes' do
    expect(subject).to be_a(described_class)
    expect(subject.name).to eq('flight-1')
    expect(subject.numberline).to eq('nl1')
    expect(subject.is_forced).to be false
    expect(subject.variant_allocation_id).to eq(352)
  end

  it 'maps to correct JSON keys' do
    mapping = described_class.attribute_map
    expect(mapping[:name]).to eq(:name)
    expect(mapping[:numberline]).to eq(:numberline)
    expect(mapping[:is_forced]).to eq(:isForced)
    expect(mapping[:variant_allocation_id]).to eq(:variantAllocationId)
  end

  it 'round-trips through JSON' do
    json = subject.to_hash.to_json
    parsed = JSON.parse(json)
    expect(parsed['name']).to eq('flight-1')
    expect(parsed['numberline']).to eq('nl1')
    expect(parsed['isForced']).to be false
    expect(parsed['variantAllocationId']).to eq(352)
  end
end
