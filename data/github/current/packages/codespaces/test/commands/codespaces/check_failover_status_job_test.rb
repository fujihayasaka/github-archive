# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class CheckFailoverStatusJobTest < GitHub::TestCase
    test "it is silent when there are no failed over regions" do
      Codespaces::VscsServiceStamp.any_instance.expects(:percent_available_for_creates).at_least_once.returns(100)
      Codespaces::VscsServiceStamp.any_instance.expects(:percent_available_for_resumes).at_least_once.returns(100)
      GitHub::Chatterbox.client.expects(:say!).never
      Codespaces::CheckFailoverStatusJob.perform_now
    end

    test "complains when a region is failed over" do
      GitHub.flipper[:codespaces_region_rejecting_creates_westus2].enable_percentage_of_actors(0)
      GitHub.flipper[:codespaces_region_rejecting_resumes_westus2].enable_percentage_of_actors(50)
      GitHub::Chatterbox.client.expects(:say!).with("#codespaces-ops", regexp_matches(/WestUs2: \(creates: 100% allowed, resumes: 50% allowed\)/))
      Codespaces::CheckFailoverStatusJob.perform_now
    end
  end
end
