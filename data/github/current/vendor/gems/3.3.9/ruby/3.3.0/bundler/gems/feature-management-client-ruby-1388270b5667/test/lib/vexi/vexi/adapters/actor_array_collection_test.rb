# frozen_string_literal: true
# typed: true

require "test_helper"
require "vexi/adapters/array_actor_collection"

class ArrayActorCollectionTest < Minitest::Test
  extend T::Sig

  describe "ArrayActorCollection" do
    describe "[]" do
      it "returns false in case there are no elements in the array" do
        actors = Vexi::Adapters::ArrayActorCollection.new([])
        refute actors["some_flag"]
      end

      it "returns false in case the element is not in the array" do
        actors = Vexi::Adapters::ArrayActorCollection.new(%w[User:1 User:10 User:2 User:3 User:4 User:5 User:6 User:7 User:8 User:9])
        refute actors["some_flag"]
      end

      it "returns true in case the element is in the array" do
        actors = Vexi::Adapters::ArrayActorCollection.new(%w[User:1 User:10 User:2 User:3 User:4 User:5 User:6 User:7 User:8 User:9])
        assert actors["User:7"]
        assert actors["User:1"]
        assert actors["User:10"]
        assert actors["User:5"]
      end
    end

    describe "each" do
      it "when the array is empty, it does not yield" do
        actors = Vexi::Adapters::ArrayActorCollection.new([])
        actors.each { |actor| fail "Should not have yielded" }
      end

      it "when the array is not empty, it yields each element" do
        actors = Vexi::Adapters::ArrayActorCollection.new(%w[User:1 User:10 User:2 User:3])
        yielded_actors = []
        actors.each { |actor| yielded_actors << actor }

        # Assert the elements are [["User:1", true], ["User:10", true], ["User:2", true], ["User:3", true]]
        assert_equal 4, yielded_actors.size
        assert_equal ["User:1", true], yielded_actors[0]
        assert_equal ["User:10", true], yielded_actors[1]
        assert_equal ["User:2", true], yielded_actors[2]
        assert_equal ["User:3", true], yielded_actors[3]
      end
    end

    describe "keys" do
      it "returns an empty array in case there are no elements in the array" do
        actors = Vexi::Adapters::ArrayActorCollection.new([])
        assert_equal [], actors.keys
      end

      it "returns the array of actors" do
        actors = Vexi::Adapters::ArrayActorCollection.new(%w[User:1 User:10 User:2 User:3])
        assert_equal %w[User:1 User:10 User:2 User:3], actors.keys
      end
    end

    describe "length" do
      it "returns 0 in case there are no elements in the array" do
        actors = Vexi::Adapters::ArrayActorCollection.new([])
        assert_equal 0, actors.length
      end

      it "returns the number of actors in the array" do
        actors = Vexi::Adapters::ArrayActorCollection.new(%w[User:1 User:10 User:2 User:3])
        assert_equal 4, actors.length
      end
    end

    describe "values" do
      it "returns an empty array in case there are no elements in the array" do
        actors = Vexi::Adapters::ArrayActorCollection.new([])
        assert_equal [], actors.values
      end

      it "returns an array of true values" do
        actors = Vexi::Adapters::ArrayActorCollection.new(%w[User:1 User:10 User:2 User:3])
        assert_equal [true, true, true, true], actors.values
      end
    end

    describe "inspect" do
      it "returns the string representation of the actors" do
        actors = Vexi::Adapters::ArrayActorCollection.new(%w[User:1 User:10 User:2 User:3])
        assert_equal "Vexi::Adapters::ArrayActorCollection([\"User:1\", \"User:10\", \"User:2\", \"User:3\"])", actors.inspect
      end
    end

    describe "==" do
      it "returns false in case the object is not an ArrayActorCollection" do
        actors = Vexi::Adapters::ArrayActorCollection.new(%w[User:1 User:10 User:2 User:3])
        refute actors == "User:1"
      end

      it "returns false in case the actors are different" do
        actors1 = Vexi::Adapters::ArrayActorCollection.new(%w[User:1 User:10 User:2 User:3])
        actors2 = Vexi::Adapters::ArrayActorCollection.new(%w[User:1 User:10 User:2 User:4])
        refute actors1 == actors2
      end

      it "returns true in case the actors are the same" do
        actors1 = Vexi::Adapters::ArrayActorCollection.new(%w[User:1 User:10 User:2 User:3])
        actors2 = Vexi::Adapters::ArrayActorCollection.new(%w[User:1 User:10 User:2 User:3])
        assert actors1 == actors2
      end
    end
  end
end
