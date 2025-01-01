# typed: true
# frozen_string_literal: true

require "test_helper"

class SuspendDependentCodespacesJobTest < GitHub::TestCase
  include DogstatsTestHelpers

  setup do
    @user = create(:user)
    @organization = create(:organization)
  end

  test "can suspend codespaces for users" do
    codespaces = create_list(:codespace, 3, owner: @user)
    codespaces.each do |codespace|
      CodespacesSuspendEnvironmentJob.expects(:perform_later).with(codespace: codespace)
    end

    Codespaces::SuspendDependentCodespacesJob.perform_now(owner_id: @user.id)
  end

  test "can suspend codespaces for organizations" do
    codespaces = create_list(:codespace, 3, owner: @user, billable_owner: @organization)
    codespaces.each do |codespace|
      CodespacesSuspendEnvironmentJob.expects(:perform_later).with(codespace: codespace)
    end

    Codespaces::SuspendDependentCodespacesJob.perform_now(owner_id: @organization.id)
  end

  test "does not suspend non-provisioned codespaces for users" do
    codespaces = create_list(:codespace, 3, owner: @user, guid: nil, state: :provisioning)

    codespaces.each do |codespace|
      CodespacesSuspendEnvironmentJob.expects(:perform_later).with(codespace: codespace).never
    end

    Codespaces::SuspendDependentCodespacesJob.perform_now(owner_id: @user.id)
  end

  test "does not suspend non-provisioned codespaces for orgs" do
    codespaces = create_list(:codespace, 3, owner: @user, billable_owner: @organization, guid: nil, state: :provisioning)

    codespaces.each do |codespace|
      CodespacesSuspendEnvironmentJob.expects(:perform_later).with(codespace: codespace).never
    end

    Codespaces::SuspendDependentCodespacesJob.perform_now(owner_id: @organization.id)
  end
end
