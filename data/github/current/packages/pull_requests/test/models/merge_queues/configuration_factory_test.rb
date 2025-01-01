# typed: true
# frozen_string_literal: true

require "test_helper"

module MergeQueues
  class ConfigurationFactoryTest < GitHub::TestCase
    fixtures do
      @merge_queue = create(:merge_queue, merging_strategy: "HEADGREEN")
    end

    context ".for" do
      test "supports the HEADGREEN merging strategy" do
        config = ConfigurationFactory.build(@merge_queue)

        assert_equal IConfiguration::GroupingStrategy::HeadGreen, config.grouping_strategy
      end

      test "supports the ALLGREEN merging strategy" do
        @merge_queue.update!(merging_strategy: "ALLGREEN")
        config = ConfigurationFactory.build(@merge_queue)

        assert_equal IConfiguration::GroupingStrategy::AllGreen, config.grouping_strategy
      end

      test "handles invalid merging strategies" do
        @merge_queue.merging_strategy = "SOMEPURPLE"
        config = ConfigurationFactory.build(@merge_queue)

        assert_equal IConfiguration::GroupingStrategy::AllGreen, config.grouping_strategy
      end

      test "handles 0 values for check response timeout" do
        # NOTE: We use `#update_column` here because `0` is no longer a valid
        # configuration.
        @merge_queue.update_column(:check_response_timeout_minutes, 0)
        config = ConfigurationFactory.build(@merge_queue)

        assert_equal 1.minute, config.check_response_timeout
      end
    end
  end
end
