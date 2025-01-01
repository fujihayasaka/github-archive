# typed: true
# frozen_string_literal: true

require "test_helper"

class RemoveOrgMemberDataJobTest < GitHub::TestCase
  fixtures do
    @test_class = Class.new(RemoveOrgMemberDataJob) do
      def self.job_class
        GitHub::Jobs::RemoveOrgMemberSomethings
      end
    end
    ::GitHub::Jobs::RemoveOrgMemberSomethings = @test_class
  end

  test "does not perform if organization is not found" do
    organization = build(:organization, id: 999_999_999)
    user = create(:user)

    @test_class.any_instance.expects(:perform).never

    perform_enqueued_jobs(only: [RemoveOrgMemberDataJob]) do
      @test_class.perform_later(organization, user)
    end
  end

  test "does not perform if user is not found" do
    organization = create(:organization)
    user = build(:user, id: 999_999_999)

    @test_class.any_instance.expects(:perform).never

    perform_enqueued_jobs(only: [RemoveOrgMemberDataJob]) do
      @test_class.perform_later(organization, user)
    end
  end
end
