# typed: true
# frozen_string_literal: true

require "test_helper"

class ScienceEventTest < GitHub::TestCase
  fixtures do
    @name = "possum"
  end

  context ".clear" do
    test "it clears the mismatches and samples" do
      ScienceEvent.push_mismatch(@name, "{}")
      ScienceEvent.push_sample(@name, "{}")

      assert_equal 1, ScienceEvent.mismatch_count(@name)
      assert_equal 1, ScienceEvent.sample_count(@name)

      ScienceEvent.clear(@name)

      assert_equal 0, ScienceEvent.mismatch_count(@name)
      assert_equal 0, ScienceEvent.sample_count(@name)
    end
  end

  context ".push_mismatch" do
    test "adds rows for the mismatches" do
      ScienceEvent.clear(@name)
      assert_equal 0, ScienceEvent.mismatch_count(@name)

      ScienceEvent.push_mismatch(@name, "{}")

      assert_equal 1, ScienceEvent.mismatch_count(@name)
    end

    test "it ignores rows when replication delay is too large" do
      Freno.client.expects(:replication_delay).returns(2)

      ScienceEvent.clear(@name)
      assert_equal 0, ScienceEvent.mismatch_count(@name)

      ScienceEvent.push_mismatch(@name, "{}")

      assert_equal 0, ScienceEvent.mismatch_count(@name)
    end
  end

  context ".push_sample" do
    test "adds rows for the samples" do
      ScienceEvent.clear(@name)
      assert_equal 0, ScienceEvent.sample_count(@name)

      ScienceEvent.push_sample(@name, "{}")

      assert_equal 1, ScienceEvent.sample_count(@name)
    end

    test "it ignores rows when replication delay is too large" do
      Freno.client.expects(:replication_delay).returns(2)

      ScienceEvent.clear(@name)
      assert_equal 0, ScienceEvent.sample_count(@name)

      ScienceEvent.push_sample(@name, "{}")

      assert_equal 0, ScienceEvent.sample_count(@name)
    end
  end

  context ".mismatch_page" do
    test "it returns the page of mismatches as specified" do
      ScienceEvent.clear(@name)

      ScienceEvent.stub_const(:MISMATCH_DISPLAY_LIMIT, 2) do
        10.times.each do |i|
          ScienceEvent.push_mismatch(@name, i.to_s)
          ScienceEvent.push_sample(@name, (50 + i).to_s)
        end

        results = ScienceEvent.mismatch_page(name: @name, page: 3)
        assert_equal %w[5 4], results
      end
    end
  end

  context ".sample_range" do
    test "it returns the page of samples as specified" do
      ScienceEvent.clear(@name)

      ScienceEvent.stub_const(:SAMPLE_DISPLAY_LIMIT, 2) do
        10.times.each do |i|
          ScienceEvent.push_sample(@name, i.to_s)
          ScienceEvent.push_mismatch(@name, (50 + i).to_s)
        end

        results = ScienceEvent.sample_page(name: @name, page: 3)
        assert_equal %w[5 4], results
      end
    end
  end

  context ".trim_mismatches" do
    test "it deletes all but the last CAP mismatch records" do
      ScienceEvent.clear(@name)

      ScienceEvent.stub_const(:MISMATCH_CAP, 4) do
        10.times.each do |i|
          ScienceEvent.push_mismatch(@name, i.to_s)
        end

        ScienceEvent.trim_mismatches(@name)

        results = ScienceEvent.mismatches(@name).pluck(:payload)
        assert_equal %w[6 7 8 9], results
      end
    end
  end

  context ".trim_samples" do
    test "it deletes all but the last CAP sample records" do
      ScienceEvent.clear(@name)

      ScienceEvent.stub_const(:SAMPLE_CAP, 4) do
        10.times.each do |i|
          ScienceEvent.push_sample(@name, i.to_s)
        end

        ScienceEvent.trim_samples(@name)

        results = ScienceEvent.samples(@name).pluck(:payload)
        assert_equal %w[6 7 8 9], results
      end
    end
  end

  context ".all_names" do
    test "returns all the different unique experiment names" do
      ScienceEvent.push_sample("a", "a1")
      ScienceEvent.push_sample("a", "a2")
      ScienceEvent.push_sample("b", "b1")
      ScienceEvent.push_sample("b", "b2")
      ScienceEvent.push_sample("c", "c1")
      ScienceEvent.push_sample("c", "c2")

      assert_equal %w[a b c], ScienceEvent.all_names
    end
  end

  context ".trim_all" do
    test "trims the mismatches and samples, for all experiments" do
      ScienceEvent.clear(@name)
      ScienceEvent.clear("another_exp")

      ScienceEvent.stub_const(:SAMPLE_CAP, 4) do
        ScienceEvent.stub_const(:MISMATCH_CAP, 4) do
          10.times.each do |i|
            ScienceEvent.push_sample(@name, i.to_s)
            ScienceEvent.push_mismatch(@name, i.to_s)
            ScienceEvent.push_sample("another_exp", i.to_s)
            ScienceEvent.push_mismatch("another_exp", i.to_s)
          end

          ScienceEvent.trim_all

          results = ScienceEvent.mismatches(@name).pluck(:payload)
          assert_equal %w[6 7 8 9], results

          results = ScienceEvent.samples(@name).pluck(:payload)
          assert_equal %w[6 7 8 9], results

          results = ScienceEvent.mismatches("another_exp").pluck(:payload)
          assert_equal %w[6 7 8 9], results

          results = ScienceEvent.samples("another_exp").pluck(:payload)
          assert_equal %w[6 7 8 9], results
        end
      end
    end
  end
end
