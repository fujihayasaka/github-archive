# typed: true
# frozen_string_literal: true

require "test_helper"

class LegacyRemoveOrgMemberDataJobTest < GitHub::TestCase
  fixtures do
    @test_class = Class.new(LegacyRemoveOrgMemberDataJob) do
      def self.job_class
        GitHub::Jobs::LegacyRemoveOrgMemberSomethings
      end
    end
    ::GitHub::Jobs::LegacyRemoveOrgMemberSomethings = @test_class
  end

  test "returns if organization is not found" do
    organization = mock(id: 999_999_999)
    user = create(:user)

    @test_class.any_instance.expects(:perform).never

    perform_enqueued_jobs(only: [@test_class]) do
      @test_class.enqueue(organization, user)
    end
  end

  test "returns if user is not found" do
    organization = create(:organization)
    user = mock(id: 999_999_999)

    @test_class.any_instance.expects(:perform).never

    perform_enqueued_jobs(only: [@test_class]) do
      @test_class.enqueue(organization, user)
    end
  end
end
