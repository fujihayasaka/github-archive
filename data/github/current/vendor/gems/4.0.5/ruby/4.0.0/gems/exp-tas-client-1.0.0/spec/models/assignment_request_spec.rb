# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe ExpTasClient::AssignmentRequest do
  it 'creates an instance with required user_params' do
    req = described_class.new(user_params: { 'clientid' => 'abc' })
    expect(req.user_params).to eq({ 'clientid' => 'abc' })
  end

  it 'accepts optional scopes, required_variants, and blocked_variants' do
    req = described_class.new(
      user_params: { 'user_id' => 'test' },
      scopes: ['my_scope'],
      required_variants: ['variant-a'],
      blocked_variants: ['variant-b']
    )
    expect(req.scopes).to eq(['my_scope'])
    expect(req.required_variants).to eq(['variant-a'])
    expect(req.blocked_variants).to eq(['variant-b'])
  end

  it 'leaves optional fields nil when not set' do
    req = described_class.new(user_params: { 'user_id' => 'test' })
    expect(req.scopes).to be_nil
    expect(req.required_variants).to be_nil
    expect(req.blocked_variants).to be_nil
  end

  it 'maps to correct JSON keys' do
    mapping = described_class.attribute_map
    expect(mapping[:user_params]).to eq(:userParams)
    expect(mapping[:scopes]).to eq(:scopes)
    expect(mapping[:required_variants]).to eq(:requiredVariants)
    expect(mapping[:blocked_variants]).to eq(:blockedVariants)
  end

  it 'serializes optional fields correctly in JSON' do
    req = described_class.new(
      user_params: { 'clientid' => 'abc' },
      scopes: ['scope1']
    )
    json = req.to_hash.to_json
    parsed = JSON.parse(json)
    expect(parsed['userParams']).to eq({ 'clientid' => 'abc' })
    expect(parsed['scopes']).to eq(['scope1'])
  end
end
