# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe ExpTasClient::DefaultApi do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:api) do
    config = ExpTasClient::Configuration.new
    config.scheme = 'http'
    config.host = 'localhost:18080'
    config.base_path = '/api/v1'

    client = ExpTasClient::ApiClient.new(config)
    # Replace the Faraday connection with a test stub
    conn = Faraday.new(url: config.base_url) do |f|
      f.adapter :test, stubs
    end
    client.instance_variable_set(:@connection_regular, conn)

    described_class.new(client)
  end

  after { stubs.verify_stubbed_calls }

  describe '#get_treatment_assignment' do
    it 'sends a POST with the correct body and returns a parsed response' do
      response_body = {
        featureVariables: { 'my_feature' => 'variant_a' },
        assignedVariants: [
          { name: 'flight-1', numberline: 'nl1', isForced: false, variantAllocationId: 352 }
        ],
        dataVersion: 42,
        assignmentContext: 'flight-1:352;'
      }

      stubs.post('/api/v1/treatment-assignment') do |env|
        body = JSON.parse(env.body)
        expect(body['userParams']).to eq({ 'clientid' => 'abc' })
        expect(env.request_headers['Content-Type']).to eq('application/json')

        [200, { 'Content-Type' => 'application/json' }, response_body.to_json]
      end

      request = ExpTasClient::AssignmentRequest.new(user_params: { 'clientid' => 'abc' })
      result = api.get_treatment_assignment(request)

      expect(result).to be_a(ExpTasClient::AssignmentResponse)
      expect(result.data_version).to eq(42)
      expect(result.assignment_context).to eq('flight-1:352;')
      expect(result.feature_variables).to eq({ 'my_feature' => 'variant_a' })
      expect(result.assigned_variants.size).to eq(1)
      expect(result.assigned_variants.first.name).to eq('flight-1')
      expect(result.assigned_variants.first.variant_allocation_id).to eq(352)
    end

    it 'sends optional fields when provided' do
      stubs.post('/api/v1/treatment-assignment') do |env|
        body = JSON.parse(env.body)
        expect(body['scopes']).to eq(['my_scope'])
        expect(body['requiredVariants']).to eq(['variant-a'])

        [200, { 'Content-Type' => 'application/json' },
         { featureVariables: {}, assignedVariants: [], dataVersion: 0, assignmentContext: '' }.to_json]
      end

      request = ExpTasClient::AssignmentRequest.new(
        user_params: { 'user_id' => 'test' },
        scopes: ['my_scope'],
        required_variants: ['variant-a']
      )
      result = api.get_treatment_assignment(request)

      expect(result).to be_a(ExpTasClient::AssignmentResponse)
    end
  end
end
