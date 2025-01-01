# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class HydroTopicTest < GitHub::TestCase
    context "V0" do
      test "#format_version uses format version v1" do
        topic = Notifyd::HydroTopic::V0.new(target: :production)

        assert_equal Hydro::Topic::FormatVersion::V1, topic.format_version
      end

      test "#to_s returns the topic name" do
        v = Notifyd::HydroTopic::V0
        assert_equal "notifyd.v0.Notify", v.new(target: :production).to_s
        assert_equal "notifyd-staging.v0.Notify", v.new(target: :staging).to_s
      end
    end

    context "V1" do
      test "#format_version uses format version v2" do
        topic = Notifyd::HydroTopic::V1.new(target: :production)

        assert_equal Hydro::Topic::FormatVersion::V2, topic.format_version
      end

      test "#to_s returns the topic name" do
        v = Notifyd::HydroTopic::V1
        assert_equal "notifyd.v1.Notify", v.new(target: :production).to_s
        assert_equal "notifyd-staging.v1.Notify", v.new(target: :staging).to_s
      end
    end
  end
end
