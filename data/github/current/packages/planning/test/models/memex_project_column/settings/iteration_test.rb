# typed: true
# frozen_string_literal: true
require "test_helper"

class MemexProjectColumnSettingsIterationTest < GitHub::TestCase
  setup do
    @id = SecureRandom.hex(4)
  end

  context "initialization" do
    test "accepts a passed in id value" do
      iteration = subject.new({
        id: @id,
        title: "Iteration 1",
        start_date: "2021-09-06",
        duration: 14,
      })

      assert_equal @id, iteration.id
    end

    test "generates a valid id if none is passed" do
      iteration = subject.new({
        title: "Iteration 1",
        start_date: "2021-09-06",
        duration: 14,
      })

      assert iteration.id
      assert_predicate iteration, :valid?
    end
  end

  test "raises UnparseableDateError when date can not be parsed" do
    assert_raises MemexProjectColumn::Settings::Iteration::UnparseableDateError do
      subject.new({
        title: "Iteration 1",
        start_date: "lolwut",
        duration: 14,
      }).completed?
    end
  end

  context "validation" do
    test "is valid with required fields" do
      iteration = subject.new({
        id: @id,
        title: "Iteration 1",
        start_date: "2021-09-06",
        duration: 14,
      })
      assert_predicate iteration, :valid?
    end

    test "is valid if id is empty" do
      iteration = subject.new({
        # id: "id", => id not passed
        title: "Iteration 1",
        start_date: "2021-09-06",
        duration: 14,
      })
      assert_predicate iteration, :valid?
    end

    test "requires title to be non-nil" do
      iteration = subject.new({
        id: @id,
        title: nil,
        start_date: "2021-09-06",
        duration: 14,
      })
      refute_predicate iteration, :valid?
    end

    test "requires start_date to be non-nil" do
      iteration = subject.new({
        id: @id,
        title: "Iteration 1",
        # start_date: "2021-09-06",
        duration: 14,
      })
      refute_predicate iteration, :valid?
    end

    test "requires duration to be non-nil" do
      iteration = subject.new({
        id: @id,
        title: "Iteration 1",
        start_date: "2021-09-06",
        # duration: 14,
      })
      refute_predicate iteration, :valid?
    end

    test "requires start_date to be a valid date in the YYYY-MM-dd format" do
      iteration = subject.new({
        id: @id,
        title: "Iteration 1",
        start_date: "invalid-date",
        duration: 14,
      })
      refute_predicate iteration, :valid?
      iteration = subject.new({
        id: @id,
        title: "Iteration 1",
        start_date: "2023-01-99",
        duration: 14,
      })
      refute_predicate iteration, :valid?
      iteration = subject.new({
        id: @id,
        title: "Iteration 1",
        start_date: "2023-99-01",
        duration: 14,
      })
      refute_predicate iteration, :valid?
      iteration = subject.new({
        id: @id,
        title: "Iteration 1",
        start_date: "99999-01-01",
        duration: 14,
      })
      refute_predicate iteration, :valid?
    end

    test "requires duration to be greater than zero" do
      iteration = subject.new({
        id: @id,
        title: "Iteration 1",
        start_date: "2021-09-06",
        duration: 0,
      })
      refute_predicate iteration, :valid?
    end

    test "requires duration to be <= to 99 weeks" do
      iteration = subject.new({
        id: @id,
        title: "Iteration 1",
        start_date: "2021-09-06",
        duration: 9_999_999,
      })
      assert_predicate iteration, :valid?

      iteration = subject.new({
        id: @id,
        title: "Iteration 1",
        start_date: "2021-09-06",
        duration: 9_999_999 + 1,
      })
      refute_predicate iteration, :valid?
    end
  end

  context "#attributes" do
    test "returns a hash of all iteration attributes" do
      config = {
        id: @id,
        title: "Iteration 1<script>alert('foo')</script>",
        start_date: "2021-09-06",
        duration: 1,
      }
      attributes = subject.new(config).attributes
      config.keys.each do |key|
        assert_equal attributes[key], config[key]
      end

      assert_equal "Iteration 1", attributes["title_html"]
    end

    test "returns a hash containing title_html if the field is not present" do
      config = {
        id: @id,
        title: "Iteration 1<script>alert('foo')</script>",
        start_date: "2021-09-06",
        duration: 1,
      }
      iteration = subject.new(config)
      iteration.instance_variable_set(:@title_html, nil)

      assert_equal "Iteration 1", iteration.attributes["title_html"]
    end
  end

  context "#completed?" do
    test "returns false when the iteration has not started" do
      iteration = subject.new(
        title: "title",
        start_date: "#{Date.today + 10.days}",
        duration: 5
      )
      refute_predicate iteration, :completed?
    end

    test "returns false when the iteration has started but the end date has not passed" do
      iteration = subject.new(
        title: "title",
        start_date: "#{Date.today - 10.days}",
        duration: 100
      )
      refute_predicate iteration, :completed?
    end

    test "returns false when the iteration has started and end date is today" do
      today = Date.parse("2022-07-14")
      Timecop.freeze(today) do
        iteration = subject.new(
          title: "title",
          start_date: "2022-07-14",
          duration: 1
        )
        refute_predicate iteration, :completed?
      end
    end

    test "returns true when the iteration has started and the end date has passed" do
      iteration = subject.new(
        title: "title",
        start_date: "#{Date.today - 10.days}",
        duration: 1
      )
      assert_predicate iteration, :completed?
    end
  end

  context "#current?" do
    test "returns false if the iteration has not yet started" do
      iteration = subject.new(
        title: "title",
        start_date: "#{Date.today + 10.days}",
        duration: 10
      )
      refute_predicate iteration, :current?
    end

    test "retuns false if the iteration is complete" do
      iteration = subject.new(
        title: "title",
        start_date: "#{Date.today - 10.days}",
        duration: 1
      )
      refute_predicate iteration, :current?
    end

    test "retuns true if the iteration has started and is not complete" do
      iteration = subject.new(
        title: "title",
        start_date: "#{Date.today - 10.days}",
        duration: 100
      )
      assert_predicate iteration, :current?
    end
  end

  context "#end_date" do
    test "returns the start_date plus the duration, minus one day" do
      iteration = subject.new(
        title: "title",
        start_date: "#{Date.yesterday}",
        duration: 3
      )
      assert_equal Date.tomorrow, iteration.end_date
    end

    test "uses the start_date when the duration is 1" do
      iteration = subject.new(
        title: "title",
        start_date: "#{Date.yesterday}",
        duration: 1
      )
      assert_equal Date.yesterday, iteration.end_date
    end

    test "uses a duration of 1 if duration is nil, instead of crashing" do
      iteration = subject.new(
        title: "title",
        start_date: "#{Date.yesterday}",
        duration: nil
      )
      assert_equal Date.yesterday, iteration.end_date
    end
  end

  private

  def subject
    MemexProjectColumn::Settings::Iteration
  end
end
