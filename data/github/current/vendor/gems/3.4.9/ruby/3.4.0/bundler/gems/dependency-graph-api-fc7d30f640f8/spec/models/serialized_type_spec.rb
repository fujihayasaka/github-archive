require "rails_helper"

describe SerializedType do
  describe ".declare" do
    it "raises an error when the given id is already taken by another type" do
      expect {
        Class.new do
          include EnumeratedType
          include SerializedType

          declare :foo, id: 1
          declare :bar, id: 1
        end
      }.to raise_error /id of 1 is already taken by foo/
    end
  end
end
