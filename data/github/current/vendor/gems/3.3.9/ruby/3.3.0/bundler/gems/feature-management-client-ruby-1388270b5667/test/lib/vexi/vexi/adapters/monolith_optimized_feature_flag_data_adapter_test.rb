# frozen_string_literal: true
# typed: true

require "test_helper"
require "vexi/adapters/monolith_optimized_feature_flag_data_adapter"

class MonolithOptimizedFeatureFlagDataAdapterTest < Minitest::Test
  extend T::Sig

  describe "MonolithOptimizedFeatureFlagDataAdapter" do
    before do
      @original_env = ENV["KUBE_CLUSTER_STAMP"]
      ENV["KUBE_CLUSTER_STAMP"] = "test"
      @client = Minitest::Mock.new
      @monolith_optmized_ffd_adapter = Vexi::Adapters::MonolithOptimizedFeatureFlagDataAdapter.new_from_env("hmac_key")
      @monolith_optmized_ffd_adapter.instance_variable_set(:@client, @client)
    end

    after do
      ENV["KUBE_CLUSTER_STAMP"] = @original_env
    end

    describe "#name" do
      it "returns feature flag adapter name" do
        assert_equal "monolith_optimized_feature_flag_data", @monolith_optmized_ffd_adapter.adapter_name
      end
    end

    describe "#feature_flag_data_url" do
      it "raises an error if the stamp environment is not configured" do
        ENV["KUBE_CLUSTER_STAMP"] = nil
        error = assert_raises(StandardError) do
          Vexi::Adapters::MonolithOptimizedFeatureFlagDataAdapter.send(:feature_flag_data_url)
        end

        assert_equal "KUBE_CLUSTER_STAMP environment variable is not set", error.message
      end

      it "returns the development feature flag data url" do
        ENV["KUBE_CLUSTER_STAMP"] = "development"
        assert_equal "http://localhost:8010/twirp", Vexi::Adapters::MonolithOptimizedFeatureFlagDataAdapter.send(:feature_flag_data_url)
      end

      it "returns the dotcom feature flag data url" do
        ENV["KUBE_CLUSTER_STAMP"] = "dotcom"
        assert_equal "https://feature-flag-data-dotcom.service.iad.github.net",
                     Vexi::Adapters::MonolithOptimizedFeatureFlagDataAdapter.send(:feature_flag_data_url)
      end

      it "returns the proxima feature flag data url otherwise" do
        stamp = ENV["KUBE_CLUSTER_STAMP"] = "production"
        assert_equal "https://feature-flag-data-#{stamp}.service.#{stamp}.github.net",
                     Vexi::Adapters::MonolithOptimizedFeatureFlagDataAdapter.send(:feature_flag_data_url)
      end
    end

    describe "#get_feature_flags" do
      it "returns multiple feature flags" do
        feature_management_ff1 = FFDV2::MonolithOptimizedFeatureFlag.new(name: "feature_flag_1",
                                                        state: :SHIPPED,
                                                        percentage_of_actors: 0.0,
                                                        percentage_of_calls: 3.4,
                                                        custom_gates: %w[gate_1
                                                                         gate_2],
                                                        segments: %w[segment_1
                                                                     segment_2],
                                                                     default_segment_actors: %w[
                                                          actor_1 actor_2
                                                        ])
        feature_management_ff2 = FFDV2::MonolithOptimizedFeatureFlag.new(name: "feature_flag_2",
                                                        state: :PARTIALLY_SHIPPED,
                                                        percentage_of_actors: 45.0,
                                                        percentage_of_calls: 2.0,
                                                        custom_gates: %w[gate_3
                                                                         gate_4],
                                                        segments: %w[segment_3
                                                                     segment_4],
                                                        default_segment_actors: %w[
                                                          actor_3 actor_4
                                                        ])

        vexi_ff1 = MonolithOptimizedFeatureFlagDataAdapterTest.convert_ffd_twirp_feature_to_vexi_feature(feature_management_ff1)
        vexi_ff2 = MonolithOptimizedFeatureFlagDataAdapterTest.convert_ffd_twirp_feature_to_vexi_feature(feature_management_ff2)

        expected_ff1_resp = Vexi::GetFeatureFlagResponse.new(name: vexi_ff1.name, feature_flag: vexi_ff1, error: nil)
        expected_ff2_resp = Vexi::GetFeatureFlagResponse.new(name: vexi_ff2.name, feature_flag: vexi_ff2, error: nil)

        resp_ff_list = [expected_ff1_resp, expected_ff2_resp]

        data = FFDV2::MonolithOptimizedGetFeatureFlagsResponse.new(feature_flags: [
                                                     feature_management_ff1, feature_management_ff2
                                                   ])
        twirp_resp = Twirp::ClientResp.new(data: data, error: nil)

        @client.expect :get_feature_flags, twirp_resp, [FFDV2::MonolithOptimizedGetFeatureFlagsRequest]
        resp = @monolith_optmized_ffd_adapter.get_feature_flags([feature_management_ff1.name, feature_management_ff2.name])

        resp.each_with_index do |ff_resp, index|
          assert_equal resp_ff_list[index]&.name, ff_resp.name
          assert_equal resp_ff_list[index]&.feature_flag&.name, ff_resp.feature_flag.name
          assert_equal resp_ff_list[index]&.feature_flag&.boolean_gate, ff_resp.feature_flag.boolean_gate
          assert_equal resp_ff_list[index]&.feature_flag&.percentage_of_actors,
                       ff_resp.feature_flag.percentage_of_actors
          assert_equal resp_ff_list[index]&.feature_flag&.percentage_of_calls, ff_resp.feature_flag.percentage_of_calls
          assert_equal resp_ff_list[index]&.feature_flag&.segments, ff_resp.feature_flag.segments
          assert_equal resp_ff_list[index]&.feature_flag&.custom_gates, ff_resp.feature_flag.custom_gates
          assert_equal resp_ff_list[index]&.feature_flag&.actors, ff_resp.feature_flag.actors
          assert_nil ff_resp.error
        end
      end

      it "raises error when response is nil" do
        @client.expect :get_feature_flags, nil,
                       [FFDV2::MonolithOptimizedGetFeatureFlagsRequest]

        error = assert_raises(StandardError) do
          @monolith_optmized_ffd_adapter.get_feature_flags(["feature_flag_1"])
        end

        assert_equal "Error fetching feature flags. Response is nil.", error.message
      end

      it "raises error when there is a error in the response" do
        resp = Twirp::ClientResp.new(data: nil,
                                     error: Twirp::Error.new(:internal,
                                                             "internal", { body: "this is an error" }))

        @client.expect :get_feature_flags, resp,
                       [FFDV2::MonolithOptimizedGetFeatureFlagsRequest]

        error = assert_raises(StandardError) do
          @monolith_optmized_ffd_adapter.get_feature_flags(["feature_flag_1"])
        end

        error_message = resp.error.meta[:body]
        assert_equal "this is an error", error_message
        assert_equal "Error fetching feature flags with status #{resp.error&.code}. Error message: '#{error_message}'",
                     error.message
      end

      it "returns error when feature flags are not found" do
        data = FFDV2::MonolithOptimizedGetFeatureFlagsResponse.new(feature_flags: [])
        resp = Twirp::ClientResp.new(data: data, error: nil)

        ff_not_found_err = Vexi::Errors::FeatureFlagNotFoundError.new("feature_flag_1")
        expected_ff1_resp = Vexi::GetFeatureFlagResponse.new(name: "feature_flag_1", feature_flag: nil,
                                                             error: ff_not_found_err)

        @client.expect :get_feature_flags, resp,
                       [FFDV2::MonolithOptimizedGetFeatureFlagsRequest]
        resp = @monolith_optmized_ffd_adapter.get_feature_flags([expected_ff1_resp.name])

        resp.each do |ff_resp|
          assert_equal expected_ff1_resp.error, ff_resp.error
        end
      end

      it "returns not found when response.data is nil" do
        resp = Twirp::ClientResp.new(data: nil, error: nil)

        @client.expect :get_feature_flags, resp, [FFDV2::MonolithOptimizedGetFeatureFlagsRequest]

        ff_not_found_err = Vexi::Errors::FeatureFlagNotFoundError.new("feature_flag_1")
        expected_ff1_resp = Vexi::GetFeatureFlagResponse.new(name: "feature_flag_1", feature_flag: nil,
                                                             error: ff_not_found_err)

        resp = @monolith_optmized_ffd_adapter.get_feature_flags([expected_ff1_resp.name])

        resp.each do |ff_resp|
          assert_equal expected_ff1_resp.error, ff_resp.error
        end
      end
    end

    describe "#get_segments" do
      it "returns multiple segments" do
        segment_ff1 = FFDV2::MonolithOptimizedSegment.new(name: "_segment_1",
                                         actors: %w[actor_1 actor_2])
        segment_ff2 = FFDV2::MonolithOptimizedSegment.new(name: "_segment_2",
                                         actors: %w[actor_3 actor_4])

        vexi_segment1 = MonolithOptimizedFeatureFlagDataAdapterTest.convert_ffd_twirp_segment_to_vexi(segment_ff1)
        vexi_segment2 = MonolithOptimizedFeatureFlagDataAdapterTest.convert_ffd_twirp_segment_to_vexi(segment_ff2)

        expected_segment1_resp = Vexi::GetSegmentResponse.new(name: vexi_segment1.name, segment: vexi_segment1,
                                                              error: nil)
        expected_segment2_resp = Vexi::GetSegmentResponse.new(name: vexi_segment2.name, segment: vexi_segment2,
                                                              error: nil)

        expected_segment_list = [expected_segment1_resp, expected_segment2_resp]

        data = FFDV2::MonolithOptimizedGetSegmentsResponse.new(segments: [segment_ff1, segment_ff2])
        twirp_resp = Twirp::ClientResp.new(data: data, error: nil)
        @client.expect :get_segments, twirp_resp, [FFDV2::GetSegmentsRequest]

        resp = @monolith_optmized_ffd_adapter.get_segments([vexi_segment1.name, vexi_segment2.name])

        resp.each_with_index do |segment_resp, index|
          assert_equal expected_segment_list[index]&.name, segment_resp.name
          assert_equal expected_segment_list[index]&.segment&.actors, segment_resp.segment.actors
          assert_equal expected_segment_list[index]&.segment&.name, segment_resp.segment.name
          assert_nil segment_resp.error
        end
      end

      it "raises error when response is nil" do
        @client.expect :get_segments, nil,
                       [FFDV2::GetSegmentsRequest]

        error = assert_raises(StandardError) do
          @monolith_optmized_ffd_adapter.get_segments(["_segment_1"])
        end

        assert_equal "Error fetching segments. Response is nil.", error.message
      end

      it "raises error when there is a error in the response" do
        resp = Twirp::ClientResp.new(data: nil, error:
                                    Twirp::Error.new(:internal, "internal", { body: "this is an error" }))

        @client.expect :get_segments, resp,
                       [FFDV2::GetSegmentsRequest]

        error = assert_raises(StandardError) do
          @monolith_optmized_ffd_adapter.get_segments(["_segment_1"])
        end

        error_message = resp.error.meta[:body]
        assert_equal "this is an error", error_message
        assert_equal "Error fetching segments with status #{resp.error&.code}. Error message: '#{error_message}'",
                     error.message
      end

      it "returns error when segment is not found" do
        data = FFDV2::MonolithOptimizedGetSegmentsResponse.new(segments: [])
        twirp_resp = Twirp::ClientResp.new(data: data, error: nil)

        segment_not_found_err = Vexi::Errors::SegmentNotFoundError.new("_segment_1")
        expected_segment_resp = Vexi::GetSegmentResponse.new(name: "_segment_1", segment: nil,
                                                             error: segment_not_found_err)

        @client.expect :get_segments, twirp_resp, [FFDV2::GetSegmentsRequest]

        expected_response = @monolith_optmized_ffd_adapter.get_segments([expected_segment_resp.name])

        expected_response.each do |segment_resp|
          assert_equal expected_segment_resp.error, segment_resp.error
        end
      end

      it "returns not found when response.data is nil" do
        resp = Twirp::ClientResp.new(data: nil, error: nil)

        @client.expect :get_segments, resp, [FFDV2::GetSegmentsRequest]

        segment_not_found_err = Vexi::Errors::SegmentNotFoundError.new("_segment_1")
        expected_segment_resp = Vexi::GetSegmentResponse.new(name: "_segment_1", segment: nil,
                                                             error: segment_not_found_err)

        expected_response = @monolith_optmized_ffd_adapter.get_segments([expected_segment_resp.name])

        expected_response.each do |segment_resp|
          assert_equal expected_segment_resp.error, segment_resp.error
        end
      end
    end
  end

  sig do
    params(ffd_twirp_feature: FFDV2::MonolithOptimizedFeatureFlag).returns(Vexi::FeatureFlag)
  end
  def self.convert_ffd_twirp_feature_to_vexi_feature(ffd_twirp_feature)
    state = ffd_twirp_feature.state.is_a?(Symbol) ?
      FFDV2::FeatureFlagState.resolve(T.cast(ffd_twirp_feature.state, Symbol)) :
      T.cast(ffd_twirp_feature.state, Integer)

    ff = Vexi::FeatureFlag.new(
      ffd_twirp_feature.name,
      boolean_gate: state == FFDV2::FeatureFlagState::SHIPPED,
      percentage_of_actors: ffd_twirp_feature.percentage_of_actors,
      percentage_of_calls: ffd_twirp_feature.percentage_of_calls,
      segments: ffd_twirp_feature.segments.to_a,
      custom_gates: ffd_twirp_feature.custom_gates.to_a,
      actors: Vexi::Adapters::ArrayActorCollection.new(ffd_twirp_feature.default_segment_actors.to_a)
    )
    ff
  end

  sig { params(ffd_twirp_segment: FFDV2::MonolithOptimizedSegment).returns(Vexi::Segment) }
  def self.convert_ffd_twirp_segment_to_vexi(ffd_twirp_segment)
    segment = Vexi::Segment.new(
      ffd_twirp_segment.name,
      actors: Vexi::Adapters::ArrayActorCollection.new(ffd_twirp_segment.actors.to_a)
    )
    segment
  end
end
