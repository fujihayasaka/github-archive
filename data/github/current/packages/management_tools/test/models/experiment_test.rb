# typed: true
# frozen_string_literal: true

require "test_helper"

class ExperimentTest < GitHub::TestCase
  fixtures do
    Experiment.delete_all
  end

  setup do
    enable_cache_storage
    reset_cache
  end

  teardown do
    reset_cache
    disable_cache_storage
  end

  test "retrieve an existing experiment" do
    experiment = Experiment.new do |e|
      e.name    = "whatevs"
      e.percent = 50
    end

    experiment.save!
    assert_equal experiment, Experiment["whatevs"]

    experiment.destroy
    refute_equal experiment, Experiment["whatevs"]
  end

  test "a new instance for a nonexistent experiment" do
    experiment = Experiment["nonexistent"]

    assert experiment.new_record?
    assert_equal "nonexistent", experiment.name
    assert_equal 0, experiment.percent
  end

  test "retrieve the percentage for an experiment" do
    experiment = Experiment["whatevs"].adjust 65

    assert_equal 65, Experiment.percentage("whatevs")
    experiment.destroy
  end

  test "requires well-formatted names" do
    experiment = Experiment["whatever no way"]
    refute experiment.valid?
    assert experiment.errors[:name]

    experiment = Experiment["this_one.is-fine.tho"]
    assert experiment.valid?
  end

  test "requires names to be unique" do
    name = "case-sensitive.experiment"
    experiment = Experiment.create!(name: name, percent: 0)

    experiment2 = Experiment.new(name: name)
    refute experiment2.valid?
    assert experiment2.errors[:name].include? "has already been taken"

    experiment3 = Experiment.new(name: name.upcase, percent: 0)
    refute experiment3.valid?
    assert experiment3.errors[:name].include? "must be lowercase, dashes, underscores, and .'s, graphite-style"
  end

  test "can clear an experiment to reset mismatch and sample data" do
    experiment = Experiment["foo.bar"]
    experiment.save!

    # clear out data
    ScienceEvent.clear(experiment.name)

    # push events
    ScienceEvent.push_mismatch(experiment.name, "{}")
    ScienceEvent.push_sample(experiment.name, "{}")

    assert_equal 1, ScienceEvent.mismatch_count(experiment.name)
    assert_equal 1, ScienceEvent.sample_count(experiment.name)

    experiment.clear

    assert_equal 0, ScienceEvent.mismatch_count(experiment.name)
    assert_equal 0, ScienceEvent.sample_count(experiment.name)
  end

  test "deletes mismatch data from redis when destroying an experiment" do
    experiment = Experiment["foo.bar"]
    experiment.save!

    ScienceEvent.clear(experiment.name)

    ScienceEvent.push_mismatch(experiment.name, "{}")

    assert_equal 1, ScienceEvent.mismatch_count(experiment.name)

    experiment.destroy

    assert_equal 0, ScienceEvent.mismatch_count(experiment.name)
  end

  test "deletes sample data from redis when destroying an experiment" do
    experiment = Experiment["foo.bar"]
    experiment.save!

    ScienceEvent.clear(experiment.name)

    ScienceEvent.push_sample(experiment.name, "{}")

    assert_equal 1, ScienceEvent.sample_count(experiment.name)

    experiment.destroy

    assert_equal 0, ScienceEvent.sample_count(experiment.name)
  end

  test "retrieving via `Experiment.percentage` uses cached percent value if available" do
    assert_equal 0, Experiment.percentage("justfor.thistest")
    GitHub.cache.set Experiment.key("justfor.thistest"), 77, 10
    assert_equal 77, Experiment.percentage("justfor.thistest")
  end

  test "reading the `#percent` attribute from an experiment bypasses percent cache" do
    experiment = Experiment["direct.access"]
    experiment.adjust("33")
    GitHub.cache.set Experiment.key("direct.access"), 77, 10
    assert_equal 33, Experiment["direct.access"].percent
    assert_equal 77, Experiment.percentage("direct.access")
  end

  test "does not have a sample threshold by default" do
    experiment = Experiment["sample.test"]
    assert_nil experiment.sample_threshold
  end

  test "does not have a sample ending time by default" do
    experiment = Experiment["sample.test"]
    assert_nil experiment.sample_ends_at
  end

  test "can set and retrieve the sample threshold" do
    experiment = Experiment["sample.test"]
    experiment.set_sample_threshold 10, 30.seconds
  end

  test "requires a non-null duration for sample thresholds" do
    experiment = Experiment["sample.test"]
    assert_raises(ArgumentError) do
      experiment.set_sample_threshold 10, nil
    end
  end

  test "can retrieve the end time for sampling" do
    experiment = Experiment["sample.test"]

    now = Time.now
    Timecop.freeze(now) do
      experiment.set_sample_threshold 10, 30.seconds
      assert_equal now + 30.seconds, experiment.sample_ends_at
    end
  end

  test "can disable sampling by setting a nil threshold" do
    experiment = Experiment["sample.test"]
    experiment.set_sample_threshold 10, 30.seconds

    assert_equal 10, experiment.sample_threshold

    experiment.set_sample_threshold nil, nil
    assert_nil experiment.sample_threshold
  end

  test "can disable sampling with the disable_sampling method" do
    experiment = Experiment["sample.test"]
    experiment.set_sample_threshold 10, 30.seconds

    assert_equal 10, experiment.sample_threshold

    experiment.disable_sampling
    assert_nil experiment.sample_threshold
  end

  test "sets a TTL for a sample threshold" do
    experiment = Experiment["sample.test"]

    now = Time.now
    Timecop.freeze(now) do
      GitHub.cache.expects(:set).with(experiment.key("sample"), [10, now + 30.seconds], 30)
      experiment.set_sample_threshold 10, 30.seconds
    end
  end

  test "tells if experiment running has been running for too long" do
    experiment = Experiment["sample.test"]
    experiment.adjust("1")

    experiment.updated_at = 1.week.ago
    assert_equal false, experiment.running_too_long?
    experiment.updated_at = 3.weeks.ago
    assert_equal true, experiment.running_too_long?
    experiment.name = "long_running.sample.test"
    assert_equal false, experiment.running_too_long?
  end

  test "can retrieve activity and mismatch rates from datadog" do
    experiment = Experiment["sample.test"]
    experiment.adjust("1")

    time_in_ms = (DateTime.now - 10.hours).to_i * 1000.to_f

    experiment_results = { "series" => [
      {
        "scope" => "experiment:#{experiment.name}",
        "pointlist" => [[time_in_ms, 20.0]],
      },
      {
        "scope" => "experiment:#{experiment.name},result:mismatch",
        "pointlist" => [[time_in_ms, 5.0]],
      },
      ] }
    GitHub.dogapi.stubs(:get_points).returns(["200", experiment_results])

    assert_equal 20.0, experiment.activity_rate
    assert_equal 5.0, experiment.mismatch_rate
  end

  context "#mismatches?" do
    test "returns true when there are associated mismatches" do
      experiment = Experiment["text_exp"]
      ScienceEvent.push_mismatch(experiment.name, "{}")

      assert experiment.mismatches?
    end

    test "returns false when there are no associated mismatches" do
      experiment = Experiment["text_exp"]

      refute experiment.mismatches?
    end
  end

  context "#currently_sampling?" do
    test "returns true when the #sample_threshold is positive" do
      experiment = Experiment["sample.test"]
      experiment.set_sample_threshold 10, 30.seconds

      assert experiment.currently_sampling?
    end

    test "returns false when the #sample_threshold is nil" do
      experiment = Experiment["sample.test"]
      experiment.set_sample_threshold nil, nil

      refute experiment.currently_sampling?
    end
  end

  context "publishes percentage change" do
    [
      { old: 0, new: 50, operation: "enabled" },
      { old: 50, new: 0, operation: "disabled" },
      { old: 50, new: 100, operation: "increased" },
    ].each do |test_case|
      test "publishes experiment #{test_case[:operation]} event to DeLorean" do
        GitHub.flipper[:disable_delorean_publishing].disable
        GitHub.stubs(:publish_events_to_delorean?).returns(true)
        GitHub.context.push(actor: build(:user, login: "fruit-salad"))

        now = Time.now.change(usec: 0)
        travel_to(now)

        name = "banana-berry"
        experiment = create(:experiment, name: name, percent: test_case[:old])

        GitHub.delorean_client.expects(:publish_event).with(
          timeline_id: 1,
          type: "science_experiment",
          operation: test_case[:operation],
          title: "Science experiment '#{name}' #{test_case[:operation]} to #{test_case[:new]}%",
          description: "fruit-salad #{test_case[:operation]} the '#{name}' science experiment " \
                       "to #{test_case[:new]}% (was #{test_case[:old]}%)",
          occurred_at: now,
          actions: {
            "Devtools": "https://admin.github.com/devtools/experiments/#{name}",
          },
          group_key: "science_experiment_#{name}",
        )
        experiment.update(percent: test_case[:new])
      end
    end
  end
end
