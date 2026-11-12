# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe ExpTasClient::ErrorResponse do
  it 'creates an instance with a message' do
    err = described_class.new(message: 'something went wrong')
    expect(err.message).to eq('something went wrong')
  end

  it 'maps to correct JSON key' do
    expect(described_class.attribute_map[:message]).to eq(:message)
  end

  it 'deserializes from a JSON hash' do
    result = described_class.build_from_hash({ 'message' => 'bad request' })
    expect(result.message).to eq('bad request')
  end
end
