# frozen_string_literal: true

require "rails_helper"

RSpec.describe Memoizable do
  subject(:item) { item_clazz.new }

  let(:item_clazz) do
    Class.new do
      include Memoizable

      attr_reader :calls

      def initialize
        @calls = Hash.new { |h, k| h[k] = 0 }
      end

      def value(item)
        memoize(:value) do
          @calls[:value] += 1
          item
        end
      end
    end
  end

  describe "#memoize" do
    context "when the result has not been memoized" do
      it "computes the result only once" do
        instance = Object.new
        2.times { expect(item.value(instance)).to eq(instance) }

        expect(item.calls[:value]).to eq(1)
      end

      it "caches a nil value to prevent duplicate calls" do
        2.times { expect(item.value(nil)).to be_nil }

        expect(item.calls[:value]).to eq(1)
      end

      it "caches a false value to prevent duplicate calls" do
        2.times { expect(item.value(false)).to be(false) }

        expect(item.calls[:value]).to eq(1)
      end
    end
  end
end
