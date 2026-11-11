# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe ExpTasClient::AssignmentResponse do
  let(:response_hash) do
    {
      feature_variables: { 'my_feature' => 'variant_a' },
      assigned_variants: [
        ExpTasClient::AssignedVariant.new(
          name: 'flight-1',
          numberline: 'nl1',
          is_forced: false,
          variant_allocation_id: 352
        )
      ],
      data_version: 42,
      assignment_context: 'flight-1:352;'
    }
  end

  subject { described_class.new(response_hash) }

  it 'creates an instance with all attributes' do
    expect(subject).to be_a(described_class)
    expect(subject.feature_variables).to eq({ 'my_feature' => 'variant_a' })
    expect(subject.data_version).to eq(42)
    expect(subject.assignment_context).to eq('flight-1:352;')
    expect(subject.assigned_variants.size).to eq(1)
    expect(subject.assigned_variants.first.name).to eq('flight-1')
  end

  it 'maps to correct JSON keys' do
    mapping = described_class.attribute_map
    expect(mapping[:feature_variables]).to eq(:featureVariables)
    expect(mapping[:assigned_variants]).to eq(:assignedVariants)
    expect(mapping[:data_version]).to eq(:dataVersion)
    expect(mapping[:assignment_context]).to eq(:assignmentContext)
  end

  it 'deserializes from a JSON hash' do
    json = {
      'featureVariables' => { 'my_feature' => 'on' },
      'assignedVariants' => [
        { 'name' => 'flight-1', 'numberline' => 'nl1', 'isForced' => false, 'variantAllocationId' => 100 }
      ],
      'dataVersion' => 7,
      'assignmentContext' => 'flight-1:100;'
    }

    result = described_class.build_from_hash(json)
    expect(result.feature_variables).to eq({ 'my_feature' => 'on' })
    expect(result.data_version).to eq(7)
    expect(result.assignment_context).to eq('flight-1:100;')
    expect(result.assigned_variants.size).to eq(1)
    expect(result.assigned_variants.first.name).to eq('flight-1')
    expect(result.assigned_variants.first.variant_allocation_id).to eq(100)
  end
end
