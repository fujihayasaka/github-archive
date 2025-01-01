# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CodespacesResizeStorageJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @codespace = create(:codespace, sku_name: "basicLinux32gb")
  end

  test "noops without an existing codespace" do
    assert_nothing_raised do
      CodespacesResizeStorageJob.perform_now(
        codespace_id: -1,
        new_sku_name: "foo",
      )
    end
  end

  test "calls ::ResizeStorage" do
    new_sku = "standardLinux32gb"
    Codespaces::ResizeStorage.expects(:call).with(@codespace, new_sku, operation: nil)
    CodespacesResizeStorageJob.perform_now(
      codespace_id: @codespace.id,
      new_sku_name: new_sku,
    )
  end

  test "if codespace is running, suspend codespace, and queue up a retry" do
    new_sku = "premiumLinux"
    Codespaces::VscsClient.any_instance.expects(:fetch_environment!).with(@codespace.guid).returns(
      { "id" => @codespace.guid, "state" => Codespaces::Vscs::State::AVAILABLE, "skuName" => @codespace.sku_name },
    )

    # Raise an error because the codespace is running
    Codespaces::VscsClient.any_instance.expects(:update_environment).with(@codespace.guid, body: { skuName: new_sku })
      .raises(Codespaces::VscsClient::InvalidUpdatingStateError.new)

    Codespaces::VscsClient.any_instance.expects(:shutdown_environment).with(@codespace.guid, repository: @codespace.repository, billable_owner: @codespace.billable_owner).returns(nil)

    CodespacesResizeStorageJob.perform_later(codespace_id: @codespace.id, new_sku_name: new_sku)

    perform_enqueued_jobs(only: [CodespacesResizeStorageJob])

    # Don't raise an error because the codespace is "shutdown"
    Codespaces::VscsClient.any_instance.expects(:update_environment).with(@codespace.guid, body: { skuName: new_sku })
      .returns(nil)

    # run enqueued jobs again because the first one setup a retry
    perform_enqueued_jobs(only: [CodespacesResizeStorageJob])

    assert_performed_jobs 2
  end

  test "retry update if codespace is still shutting down" do
    new_sku = "premiumLinux"

    Codespaces::VscsClient.any_instance.expects(:fetch_environment!).with(@codespace.guid).returns(
      { "id" => @codespace.guid, "state" => Codespaces::Vscs::State::SHUTTING_DOWN, "skuName" => @codespace.sku_name },
    )

    # Raise an error because the codespace is still shutting down
    Codespaces::VscsClient.any_instance.expects(:update_environment).with(@codespace.guid, body: { skuName: new_sku })
      .raises(Codespaces::VscsClient::InvalidUpdatingStateError.new)

    CodespacesResizeStorageJob.perform_later(codespace_id: @codespace.id, new_sku_name: new_sku)

    perform_enqueued_jobs(only: [CodespacesResizeStorageJob])

    # Don't raise an error because the codespace is "shutdown"
    Codespaces::VscsClient.any_instance.expects(:update_environment).with(@codespace.guid, body: { skuName: new_sku })
      .returns(nil)

    # run enqueued jobs again because the first one setup a retry
    perform_enqueued_jobs(only: [CodespacesResizeStorageJob])

    assert_performed_jobs 2
  end
end unless GitHub.enterprise?
