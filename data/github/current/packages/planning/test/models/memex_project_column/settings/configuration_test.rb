# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnSettingsConfigurationTest < GitHub::TestCase
  include GitHub::LoggerHelper

  context "validation" do
    test "is valid with required fields" do
      settings = subject.new({
        start_day: 1,
        duration: 14
      })
      assert_predicate settings, :valid?
    end

    test "requires start_day configuration option" do
      settings = subject.new({
        # start_day: 1,
        duration: 14
      })
      refute_predicate settings, :valid?
    end

    test "requires duration configuration option" do
      settings = subject.new({
        start_day: 1,
        # duration: 14
      })
      refute_predicate settings, :valid?
    end

    test "requires start_day, duration configuration options" \
     "to be numbers" do
      settings = subject.new({
        start_day: {},
        duration: {}
      })
      refute_predicate settings, :valid?
    end

    test "requires start_day to be between 1 and 7, not 0" do
      settings = subject.new({
        start_day: 0,
        duration: 14
      })
      refute_predicate settings, :valid?
    end

    test "requires start_day to be between 1 and 7, inclusive" do
      settings = subject.new({
        start_day: 7,
        duration: 14
      })
      assert_predicate settings, :valid?
    end

    test "requires duration to be greater than zero" do
      settings = subject.new({
        start_day: 6,
        duration: 0
      })
      refute_predicate settings, :valid?
    end

    test "requires duration to be <= to 99 weeks" do
      settings = subject.new({
        start_day: 6,
        duration: 9_999_999
      })
      assert_predicate settings, :valid?

      settings = subject.new({
        start_day: 6,
        duration: 9_999_999 + 1
      })
      refute_predicate settings, :valid?
    end

    context "iterations" do
      test "allows a nil iterations array" do
        settings = subject.new({
          start_day: 1,
          duration: 14,
          iterations: nil
        })
        assert_predicate settings, :valid?
      end

      test "allows an empty iterations array" do
        settings = subject.new({
          start_day: 1,
          duration: 14,
          iterations: []
        })
        assert_predicate settings, :valid?
      end

      test "requires iterations to be of the right shape" do
        settings = subject.new({
          start_day: 1,
          duration: 14,
          iterations: [{
            start_day: 1,
            duration: 14,
            # title: 'new' => missing title
          }]
        })
        refute_predicate settings, :valid?
      end

      test "does not allow for too many validations" do
        subject.stub_const(:MAX_ITERATION_COUNT_LIMIT, 1) do
          settings = subject.new({
            start_day: 1,
            duration: 14,
            iterations: [{
              start_date: "2021-10-01",
              duration: 14,
              title: "new"
            }],
            completed_iterations: [{
              start_date: "2021-09-16",
              duration: 14,
              title: "newish"
            }]
          })
          refute_predicate settings, :valid?
          assert_same_elements(
            ["exceeds the maximum limit of iterations allowed, 1"],
            settings.errors.full_messages
          )
        end
      end
    end

    context "completed iterations" do
      test "allows a nil completed iterations array" do
        settings = subject.new({
          start_day: 1,
          duration: 14,
          completed_iterations: nil
        })
        assert_predicate settings, :valid?
      end

      test "allows an empty completed iterations array" do
        settings = subject.new({
          start_day: 1,
          duration: 14,
          completed_iterations: []
        })
        assert_predicate settings, :valid?
      end

      test "requires completed iterations to be of the right shape" do
        settings = subject.new({
          start_day: 1,
          duration: 14,
          completed_iterations: [{
            start_day: 1,
            duration: 14,
            # title: 'new' => missing title
          }]
        })
        refute_predicate settings, :valid?
      end
    end
  end

  context "#serialize" do
    test "returns a hash of configuration attributes" do
      config_options = {
        start_day: 6,
        duration: 2,
        iterations: [
          {
            "id" => SecureRandom.hex(4),
            "title" => "ohai there",
            "start_date" => "2021-09-06",
            "duration" => 14,
          }
        ],
        completed_iterations: [
          {
            "id" => SecureRandom.hex(4),
            "title" => "ohai there, friend",
            "start_date" => "2021-08-06",
            "duration" => 14,
          }
        ]
      }

      serialized = subject
        .new(config_options)
        .serialize

      expected = config_options.deep_dup

      # title_html is a sanitized copy of iterations & completed_iterations title
      expected[:iterations] = expected[:iterations].each { |i| i["title_html"] = i["title"] }
      expected[:completed_iterations] = expected[:completed_iterations].each { |i| i["title_html"] = i["title"] }

      config_options.keys.each do |key|
        assert_equal expected[key], serialized[key]
      end
    end

    test "compacts nil/weird values" do
      config_options = {
        start_day: 6,
        duration: {}
      }

      serialized = subject
        .new(config_options)
        .serialize

      assert_equal 6, serialized[:start_day]
      assert_nil serialized[:duration]
    end
  end

  context "#partition_iterations" do
    test "ensures that misplaced active iterations are moved to completed" do
      config_options = {
        start_day: 6,
        duration: 2,
        iterations: [
          {
            "id" => SecureRandom.hex(4),
            "title" => "ohai there",
            "start_date" => "#{Date.today - 10.months}", # that should be completed
            "duration" => 14,
          }
        ],
        completed_iterations: []
      }

      result = subject.new(config_options).partition_iterations
      assert_empty result.iterations
      assert_equal 1, result.completed_iterations.size
    end

    test "ensures that misplaced completed_iterations are moved to iterations" do
      config_options = {
        start_day: 6,
        duration: 2,
        iterations: [],
        completed_iterations: [
          {
            "id" => SecureRandom.hex(4),
            "title" => "ohai there",
            "start_date" => "#{Date.yesterday}", # that should be active
            "duration" => 14,
          }
        ],
      }

      result = subject.new(config_options).partition_iterations
      assert_empty result.completed_iterations
      assert_equal 1, result.iterations.size
    end

    test "ensures that duplicate active iterations by start_date are removed" do
      config_options = {
        start_day: 6,
        duration: 2,
        completed_iterations: [],
        iterations: [
          {
            "id" => SecureRandom.hex(4),
            "title" => "ohai there",
            "start_date" => "#{Date.today}", # same start
            "duration" => 14,
          },
          {
            "id" => SecureRandom.hex(4),
            "title" => "not the same title",
            "start_date" => "#{Date.today}", # same start
            "duration" => 14,
          }
        ],
      }

      expected_log_tags = {
        Body: MemexProjectColumn::Settings::Configuration::DUPLICATE_ITERATION_MESSAGE,
        "gh.memex.iteration.id": config_options[:iterations].second["id"],
        "gh.memex.iteration.title": config_options[:iterations].second["title"],
        "gh.memex.iteration.start_date": config_options[:iterations].second["start_date"],
        "gh.memex.iteration.duration": config_options[:iterations].second["duration"],
      }

      assert_logged **expected_log_tags do
        result = subject.new(config_options).partition_iterations
        assert_equal 1, result.iterations.size
      end
    end

    test "ensures that duplicate completed_iterations by start_date are removed" do
      config_options = {
        start_day: 6,
        duration: 2,
        iterations: [],
        completed_iterations: [
          {
            "id" => SecureRandom.hex(4),
            "title" => "ohai there",
            "start_date" => "#{Date.today - 10.weeks}", # same start
            "duration" => 14,
          },
          {
            "id" => SecureRandom.hex(4),
            "title" => "not the same title",
            "start_date" => "#{Date.today - 10.weeks}", # same start
            "duration" => 14,
          }
        ],
      }

      expected_log_tags = {
        Body: MemexProjectColumn::Settings::Configuration::DUPLICATE_ITERATION_MESSAGE,
        "gh.memex.iteration.id": config_options[:completed_iterations].second["id"],
        "gh.memex.iteration.title": config_options[:completed_iterations].second["title"],
        "gh.memex.iteration.start_date": config_options[:completed_iterations].second["start_date"],
        "gh.memex.iteration.duration": config_options[:completed_iterations].second["duration"],
      }

      assert_logged **expected_log_tags do
        result = subject.new(config_options).partition_iterations
        assert_equal 1, result.completed_iterations.size
      end
    end

    test "ensures that iterations are ordered by start_date asc" do
      earlier_id = SecureRandom.hex(4)
      later_id = SecureRandom.hex(4)

      config_options = {
        start_day: 6,
        duration: 2,
        completed_iterations: [],
        iterations: [
          {
            "id" => later_id,
            "title" => "ohai there",
            "start_date" => "#{Date.today + 14.days}",
            "duration" => 14,
          },
          {
            "id" => earlier_id,
            "title" => "not the same title",
            "start_date" => "#{Date.today}",
            "duration" => 14,
          }
        ],
      }

      result = subject.new(config_options).partition_iterations
      assert_equal [earlier_id, later_id], result.iterations.map(&:id)
    end

    test "ensures that completed_iterations are ordered by start_date desc" do
      earlier_id = SecureRandom.hex(4)
      later_id = SecureRandom.hex(4)

      config_options = {
        start_day: 6,
        duration: 2,
        iterations: [],
        completed_iterations: [
          {
            "id" => later_id,
            "title" => "ohai there",
            "start_date" => "#{Date.today - 29.days}",
            "duration" => 14,
          },
          {
            "id" => earlier_id,
            "title" => "not the same title",
            "start_date" => "#{Date.today - 15}",
            "duration" => 14,
          }
        ],
      }

      result = subject.new(config_options).partition_iterations
      assert_equal [earlier_id, later_id], result.completed_iterations.map(&:id)
    end
  end

  private

  def subject
    MemexProjectColumn::Settings::Configuration
  end
end
