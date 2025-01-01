# typed: true
# frozen_string_literal: true

require "test_helper"

class MigrationTimingTest < GitHub::TestCase
  fixtures do
    @migration_timing = create(:migration_timing)
    @migration = create(:migration)
  end

  ##
  # Validations
  #
  test "the factory is valid" do
    assert @migration_timing.valid?
  end

  test "it requires a migration" do
    @migration_timing.migration = nil
    assert @migration_timing.invalid?
  end

  test "it requires an action" do
    @migration_timing.action = nil
    assert @migration_timing.invalid?
  end

  test "it requires a time_elapsed" do
    @migration_timing.time_elapsed = nil
    assert @migration_timing.invalid?
  end

  ##
  # MigrationTiming.record
  #
  test ".record times an action for a migration" do
    now = Time.now

    assert_difference("MigrationTiming.count", 1) do
      Timecop.freeze(now) do
        MigrationTiming.record(@migration, :import) do
          Timecop.travel(now + 20.seconds)
        end
      end
    end

    migration_timing = MigrationTiming.last
    migration_timing = T.must(migration_timing)

    assert_equal @migration, migration_timing.migration
    assert_equal "import", migration_timing.action
    assert_equal 20, migration_timing.time_elapsed
  end

  test ".record returns the result of the block" do
    result = MigrationTiming.record(@migration, :import) { 25 }
    assert_equal 25, result
  end
end
