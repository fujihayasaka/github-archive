# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryAddingAndRemovingUserLicensesWhenLicensingStatusChangesTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @business = create(:business)
    @business_owned_organization = create(:organization, business: @business)

    @business_owned_repository = create(:private_repository, owner: @business_owned_organization, active: true)

    @standalone_organization = create(:organization)
    @standalone_repository = create(:private_repository, owner: @standalone_organization, active: true)

    @user = create(:user)
  end

  context "adding and removing members" do
    test "publishes license snapshot events when a user is added or removed from a repository that's owned by an organization in an enterprise account" do
      perform_enqueued_jobs(only: Licensing::SnapshotLicensesJob) do
        @business_owned_repository.add_member(@user)

        assert_hydro_messages(count: 2, schema: "github.billing.v0.LicenseSnapshot")

        @business_owned_repository.remove_member(@user)

        assert_hydro_messages(count: 3, schema: "github.billing.v0.LicenseSnapshot")
      end
    end

    test "does not publish license snapshot events when a user is added or removed from a repository that's not owned by an organization in an enterprise account" do
      perform_enqueued_jobs(only: Licensing::SnapshotLicensesJob) do
        @standalone_repository.add_member(@user)
        @standalone_repository.remove_member(@user)
      end

      assert_hydro_messages(count: 0, schema: "github.billing.v0.LicenseSnapshot")
    end
  end

  context "changing active status" do
    test "publishes license snapshot events when the active flag is changed for a repository that's owned by an organization in an enterprise account" do
      perform_enqueued_jobs(only: Licensing::SnapshotLicensesJob) do
        @business_owned_repository.update(active: nil)
        assert_hydro_messages(count: 1, schema: "github.billing.v0.LicenseSnapshot")

        @business_owned_repository.update(active: true)
        assert_hydro_messages(count: 2, schema: "github.billing.v0.LicenseSnapshot")
      end
    end

    test "does not publish license snapshot events when the active flag is changed for a repository that's not owned by an organization in an enterprise account" do
      perform_enqueued_jobs(only: Licensing::SnapshotLicensesJob) do
        @standalone_repository.update(active: nil)
        @standalone_repository.update(active: true)
      end

      assert_hydro_messages(count: 0, schema: "github.billing.v0.LicenseSnapshot")
    end
  end

  context "changing visibility" do
    test "publishes license snapshot events when the public flag is changed for a repository that's owned by an organization in an enterprise account" do
      perform_enqueued_jobs(only: Licensing::SnapshotLicensesJob) do
        @business_owned_repository.update(public: true)
        assert_hydro_messages(count: 1, schema: "github.billing.v0.LicenseSnapshot")
        @business_owned_repository.update(public: false)
        assert_hydro_messages(count: 2, schema: "github.billing.v0.LicenseSnapshot")
      end
    end

    test "does not publish license snapshot events when the public flag is changed for a repository that's not owned by an organization in an enterprise account" do
      perform_enqueued_jobs(only: Licensing::SnapshotLicensesJob) do
        @standalone_repository.update(public: false)
        @standalone_repository.update(public: true)
      end

      assert_hydro_messages(count: 0, schema: "github.billing.v0.LicenseSnapshot")
    end
  end

  context "transforming ownership" do
    test "publishes license snapshot events when the ownership is changed for a repository that's owned by an organization in an enterprise account to one that isn't" do
      perform_enqueued_jobs(only: [Licensing::SnapshotLicensesJob, RepositoryOrchestrationJob]) do
        @business_owned_repository.transfer_ownership_to(@standalone_organization, actor: @business_owned_organization.admins.first)
      end

      assert_hydro_messages(count: 1, schema: "github.billing.v0.LicenseSnapshot")
    end

    test "publishes license snapshot events when the ownership is changed for a repository that's not owned by an organization in an enterprise account to one that is" do
      perform_enqueued_jobs(only: [Licensing::SnapshotLicensesJob, RepositoryOrchestrationJob]) do
        @standalone_repository.transfer_ownership_to(@business_owned_organization, actor: @standalone_organization.admins.first)
      end

      assert_hydro_messages(count: 1, schema: "github.billing.v0.LicenseSnapshot")
    end

    test "publishes license snapshot events when the ownership is changed for a repository that's owned by an organization in an enterprise account to another one that is also in an enterprise account" do
      another_business_owned_organization = create(:organization, business: create(:business))
      reset_hydro # clear any messages that were sent during setup

      perform_enqueued_jobs(only: [Licensing::SnapshotLicensesJob, RepositoryOrchestrationJob]) do
        @business_owned_repository.transfer_ownership_to(another_business_owned_organization, actor: @business_owned_organization.admins.first)
      end

      assert_hydro_messages(count: 2, schema: "github.billing.v0.LicenseSnapshot")
    end
  end
end if GitHub.billing_enabled?
