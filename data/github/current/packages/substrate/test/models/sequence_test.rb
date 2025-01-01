# typed: false
# frozen_string_literal: true

require "test_helper"

class SequenceTest < GitHub::TestCase
  fixtures do
    @integration  = create(:integration)
    @integration2 = create(:integration)

    @repo = create(:repository)
    @milestone = create :milestone, repository: @repo, created_by: @repo.owner, due_on: Time.now + 1.month
  end

  context "next" do
    test "starts at 1" do
      assert_equal 1, Sequence.next(@integration)
    end

    test "advances to 2" do
      Sequence.next(@integration)
      assert_equal 2, Sequence.next(@integration)
    end

    test "maintains distinct counts by context" do
      assert_equal 1, Sequence.next(@integration)
      assert_equal 1, Sequence.next(@integration2)

      assert_equal 2, Sequence.next(@integration)
      assert_equal 2, Sequence.next(@integration2)
    end

    test "raises if the sequence doesn't exist" do
      Sequence.reset(@integration)
      refute Sequence.exists?(@integration), "sequence should not exist"
      assert_raises(Sequence::Error) do
        Sequence.next(@integration)
      end
    end

    test "advances arbitrary amounts" do
      assert_equal 1, Sequence.next(@integration)
      assert_equal 11, Sequence.next(@integration, 10)
      assert_equal 12, Sequence.next(@integration)
    end
  end

  context "set" do
    test "sets the current number" do
      Sequence.set(@integration, 50)
      assert_equal 50, Sequence.get(@integration)
    end

    test "noop when sequence doesn't exist" do
      Sequence.reset(@integration)
      Sequence.set(@integration, 50)
      assert !Sequence.exists?(@integration), "sequence should not exist"
      assert_equal 0, Sequence.get(@integration)
    end
  end

  context "reset" do
    test "resets the sequence to zero" do
      Sequence.next(@integration)
      Sequence.reset(@integration)
      assert_equal 0, Sequence.get(@integration)
    end

    test "removes the sequence" do
      assert Sequence.exists?(@integration), "sequence should exist"
      Sequence.reset(@integration)
      assert !Sequence.exists?(@integration), "sequence should not exist"
    end
  end

  context "get" do
    test "finds the current number" do
      assert_equal 1, Sequence.next(@integration)
      assert_equal 1, Sequence.get(@integration)
    end

    test "defaults to zero" do
      assert_equal 0, Sequence.get(@integration)
    end
  end

  context "exists?" do
    test "returns true when sequence exists" do
      assert Sequence.exists?(@integration), "sequence should exist"
    end

    test "returns false when sequence does not exist" do
      Sequence.reset(@integration)
      assert !Sequence.exists?(@integration), "sequence should not exist"
    end
  end

  context "create" do
    test "creates non-existent sequence" do
      Sequence.reset(@integration)
      assert !Sequence.exists?(@integration), "sequence should not exist"
      Sequence.create(@integration)
      assert Sequence.exists?(@integration), "sequence should exist"
    end

    test "creates and sets if the sequence is specified" do
      Sequence.reset(@integration)
      assert !Sequence.exists?(@integration), "sequence should not exist"
      Sequence.create(@integration, 50)
      assert_equal 50, Sequence.get(@integration)
    end

    test "fails to create an existing sequence" do
      num = Sequence.next(@integration)
      Sequence.create(@integration)
      assert_equal num, Sequence.get(@integration)
    end
  end

  context "internal: prepare_query_bindings creates bindings for context" do
    test "accepts an object" do
      sql_bindings = Sequence.prepare_query_bindings(@integration)
      assert_equal "Integration", sql_bindings[:context_type]
    end
  end

  context "extracted contexts" do
    test "create does write to the correct sequence table" do
      Sequence.reset(@repo)

      refute Sequence.exists?(@repo)
      assert_nil @repo.repository_sequence

      Sequence.create(@repo)

      assert Sequence.exists?(@repo)
      assert_equal 0, Sequence.get(@repo)

      refute_nil @repo.reload.repository_sequence
      assert_equal 0, @repo.repository_sequence.number
    end

    test "next does write to the correct table" do
      refute_nil @repo.reload.repository_sequence

      number = Sequence.next(@repo)
      assert_equal 1, number

      assert_equal number, @repo.repository_sequence.reload.number
    end

    test "set does write to the correct table" do
      refute_nil @repo.reload.repository_sequence

      Sequence.set(@repo, 42)
      assert_equal 42, Sequence.get(@repo)

      assert_equal 42, @repo.repository_sequence.reload.number
    end

    test "reset does write to the correct table" do
      refute_nil @repo.reload.repository_sequence

      Sequence.reset(@repo)

      refute Sequence.exists?(@repo)
      assert_nil @repo.reload.repository_sequence
    end
  end

  context "uses milestone specific sequence table when applicable" do
    test "get and create uses the correct table" do
      assert_equal @milestone.number, Sequence.get(@milestone)

      sequence_number = RepositoryMilestonesSequence.find_by_repository_id(@repo.id).number
      assert_equal @milestone.number, sequence_number
    end

    test "set uses the correct table" do
      number = 123

      Sequence.set @milestone, number
      assert_equal number, Sequence.get(@milestone)

      sequence_number = RepositoryMilestonesSequence.find_by_repository_id(@repo.id).number
      assert_equal number, sequence_number
    end

    test "exists? uses the correct table" do
      assert Sequence.exists?(@milestone)
      assert RepositoryMilestonesSequence.exists?(repository_id: @repo.id)
    end

    test "reset uses the correct table" do
      Sequence.reset @milestone

      refute Sequence.exists?(@milestone)
      refute RepositoryMilestonesSequence.exists?(repository_id: @repo.id)
    end
  end
end
