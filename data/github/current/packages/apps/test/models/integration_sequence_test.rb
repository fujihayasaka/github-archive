# typed: true
# frozen_string_literal: true

require "test_helper"
class IntegrationSequenceDependencyMethodsTest < GitHub::TestCase
  class FakeIntegration

    include Integration::Sequence

    class << self
      attr_accessor :after_create_callback
    end

    def self.after_create(callback)
      @after_create_callback = callback
    end

    attr_reader :id

    def initialize(id)
      @id = id
    end

    def self.<=(klass)
      # stubbing this allows us to not include this class in Sorbet Types
      klass == Integration
    end
  end

  setup do
    @integration = FakeIntegration.new(1)
  end

  teardown do
    FakeIntegration.after_create(nil)
  end

  test "creates a sequence when a integration is created" do
    assert !Sequence.exists?(@integration), "sequence should not exist"
    @integration.create_sequence
    assert Sequence.exists?(@integration), "sequence should exist"
  end

  test "sets the create_sequence method as an after_create callback" do
    assert_nil FakeIntegration.after_create_callback
    FakeIntegration.setup_sequence
    assert_equal :create_sequence, FakeIntegration.after_create_callback
  end
end
