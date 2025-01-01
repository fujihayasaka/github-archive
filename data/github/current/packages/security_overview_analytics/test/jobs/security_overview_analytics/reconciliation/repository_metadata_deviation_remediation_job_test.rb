# typed: strict
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Reconciliation
    class RepositoryMetadataDeviationRemediationJobTest < GitHub::TestCase
      include DogstatsTestHelpers

      RepositoryMetadata = ::SecurityOverviewAnalytics::Repository

      fixtures do
        # Business
        if GitHub.enterprise?
          @biz = T.let(create(:global_business), T.nilable(::Business))
          @user = T.let(create(:user, business: @biz), T.nilable(::User))
        else
          @biz = T.let(create(:business, :enterprise_managed), T.nilable(::Business))
          @user = T.let(create(:emu, business: @biz), T.nilable(::User))
        end
      end

      setup do
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)
        Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::RepositoryMetadata).returns(true)
      end

      context "#perform for organization" do
        context "when repository metadata record doesn't exist" do
          test "does nothing if repository doesn't exist neither" do
            org = create(:organization)
            repo = create(:repository, owner: org)
            repository_id = repo.id
            repo.destroy!
            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repository_id)
              end
            end
            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "does nothing if repository is deleted" do
            user = create(:user)
            org = create(:organization)
            repo = create(:repository, owner: org)
            repo.remove(user)
            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repo.id)
              end
            end
            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "does nothing if repository owner is out of scope" do
            TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)
            org = create(:organization)
            repo = create(:repository, owner: org)
            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repo.id)
              end
            end
            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "does nothing if repository owner is not initialized" do
            Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::RepositoryMetadata).returns(false)
            org = create(:organization)
            repo = create(:repository, owner: org)
            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repo.id)
              end
            end
            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "creates missing metadata record for legit repository" do
            org = create(:organization, business: @biz, admin: @user)
            repo = create(:repository, owner: org)
            refute RepositoryMetadata.find_by(repository_id: repo.id)
            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repo.id)
              end
            end

            metadata = RepositoryMetadata.find_by(repository_id: repo.id)

            assert metadata
            assert_equal org.business.id, metadata&.business_id
            assert_equal org.id, metadata&.owner_id
            assert_equal "ORGANIZATION", metadata&.owner_type

            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:metadata_created"
            ]
          end
        end

        context "when repository metadata record exists" do
          test "deletes metadata record if repository doesn't exist" do
            metadata = create(:security_overview_analytics_repository)
            metadata.repository.destroy!
            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: metadata.repository_id)
              end
            end
            assert_nil RepositoryMetadata.find_by(repository_id: metadata.repository_id)
            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:metadata_deleted"
            ]
          end

          test "deletes metadata record if repository is deleted" do
            user = create(:user)
            metadata = create(:security_overview_analytics_repository)
            metadata.repository.remove(user)
            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: metadata.repository_id)
              end
            end
            assert_nil RepositoryMetadata.find_by(repository_id: metadata.repository_id)
            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:metadata_deleted"
            ]
          end

          test "deletes metadata record if repository owner is out of scope" do
            TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)
            metadata = create(:security_overview_analytics_repository)
            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: metadata.repository_id)
              end
            end
            assert_nil RepositoryMetadata.find_by(repository_id: metadata.repository_id)
            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:metadata_deleted"
            ]
          end

          test "deletes metadata record if repository owner is not initialized" do
            Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::RepositoryMetadata).returns(false)
            metadata = create(:security_overview_analytics_repository)
            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: metadata.repository_id)
              end
            end
            assert_nil RepositoryMetadata.find_by(repository_id: metadata.repository_id)
            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:metadata_deleted"
            ]
          end

          test "updates metadata organization_id for legit repository" do
            org = create(:organization)
            metadata = create(:security_overview_analytics_repository)
            metadata.repository.update(owner_id: org.id)
            refute_equal org.id, metadata.reload.organization_id

            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: metadata.repository_id)
              end
            end
            assert_equal org.id, metadata.reload.organization_id
            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:metadata_updated"
            ]
          end

          test "updates metadata repository name for legit repository" do
            new_name = "hahaha"
            metadata = create(:security_overview_analytics_repository)
            metadata.repository.update(name: new_name)
            refute_equal new_name, metadata.reload.name

            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: metadata.repository_id)
              end
            end
            assert_equal new_name, metadata.reload.name
            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:metadata_updated"
            ]
          end

          test "updates metadata repository visibility for legit repository" do
            admin = create(:user)
            org = create(:organization, admin: admin)
            repo = create(:repository, owner: org)
            metadata = create(:security_overview_analytics_repository, repository: repo)

            new_visibility = "private"
            repo.set_visibility(actor: admin, visibility: new_visibility)
            refute_equal new_visibility, metadata.reload.visibility

            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: metadata.repository_id)
              end
            end
            assert_equal new_visibility, metadata.reload.visibility
            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:metadata_updated"
            ]
          end

          test "updates metadata repository archived for legit repository" do
            metadata = create(:security_overview_analytics_repository)
            metadata.repository.set_archived
            refute metadata.reload.archived

            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: metadata.repository_id)
              end
            end
            assert metadata.reload.archived
            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:metadata_updated"
            ]
          end

          test "updates metadata repository pushed_at for legit repository" do
            new_pushed_at = Time.current
            metadata = create(:security_overview_analytics_repository)
            metadata.repository.update(pushed_at: new_pushed_at)
            refute_equal new_pushed_at, metadata.reload.pushed_at

            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: metadata.repository_id)
              end
            end
            assert_equal new_pushed_at&.to_i, metadata.reload.pushed_at&.to_i
            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:metadata_updated"
            ]
          end

          test "updates metadata event_time when updates the record" do
            metadata = create(:security_overview_analytics_repository)
            assert_changes(
              -> { metadata.reload.event_time }
            ) do
              perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
                assert_nothing_raised do
                  RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: metadata.repository_id)
                end
              end
              assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
                "remediation:metadata_updated"
              ]
            end
          end

          test "updates metadata updated_at when updates the record" do
            metadata = create(:security_overview_analytics_repository)
            assert_changes(
              -> { metadata.reload.updated_at }
            ) do
              perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
                assert_nothing_raised do
                  RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: metadata.repository_id)
                end
              end
              assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
                "remediation:metadata_updated"
              ]
            end
          end
        end
      end

      context "#perform for user" do
        context "when repository metadata record doesn't exist" do
          test "does nothing if repository doesn't exist neither" do
            repo = create(:repository, owner: @user)
            repository_id = repo.id
            repo.destroy!

            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repository_id)
              end
            end

            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "does nothing if repository is deleted" do
            repo = create(:repository, owner: @user)
            repo.remove(@user)

            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repo.id)
              end
            end

            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "does nothing if repository is out of of scope" do
            TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)
            repo = create(:repository, owner: @user)

            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repo.id)
              end
            end

            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "does nothing if repository owner is not initialized" do
            Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::RepositoryMetadata).returns(false)
            repo = create(:repository, owner: @user)

            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repo.id)
              end
            end

            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "creates missing metadata record for legit repository" do
            repo = create(:repository, owner: @user)
            refute RepositoryMetadata.find_by(repository_id: repo.id)
            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repo.id)
              end
            end

            metadata = RepositoryMetadata.find_by(repository_id: repo.id)

            assert metadata
            assert_equal 0, metadata&.organization_id
            assert_equal @biz&.id, metadata&.business_id
            assert_equal @user&.id, metadata&.owner_id
            assert_equal "USER", metadata&.owner_type

            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:metadata_created"
            ]
          end
        end

        context "when repository metadata record exists" do
          test "deletes metadata record if repository doesn't exist" do
            repo = create(:repository, owner: @user)
            metadata = create(:security_overview_analytics_repository, repository: repo)
            metadata.repository.destroy!

            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: metadata.repository_id)
              end
            end

            assert_nil RepositoryMetadata.find_by(repository_id: metadata.repository_id)
            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:metadata_deleted"
            ]
          end

          test "deletes metadata record if repository is deleted" do
            repo = create(:repository, owner: @user)
            metadata = create(:security_overview_analytics_repository, repository: repo)
            metadata.repository.remove(@user)

            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: metadata.repository_id)
              end
            end

            assert_nil RepositoryMetadata.find_by(repository_id: metadata.repository_id)
            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:metadata_deleted"
            ]
          end

          test "deletes metadata record if repository owner is out of scope" do
            TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)
            repo = create(:repository, owner: @user)
            metadata = create(:security_overview_analytics_repository, repository: repo)

            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: metadata.repository_id)
              end
            end

            assert_nil RepositoryMetadata.find_by(repository_id: metadata.repository_id)
            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:metadata_deleted"
            ]
          end

          test "deletes metadata record if repository owner is not initialized" do
            Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::RepositoryMetadata).returns(false)
            repo = create(:repository, owner: @user)
            metadata = create(:security_overview_analytics_repository, repository: repo)

            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: metadata.repository_id)
              end
            end

            assert_nil RepositoryMetadata.find_by(repository_id: metadata.repository_id)
            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:metadata_deleted"
            ]
          end

          test "updates metadata owner_id and owner_type for legit repository" do
            metadata = create(:security_overview_analytics_repository)
            metadata.repository.update(owner_id: @user&.id)
            refute_equal @user&.id, metadata.reload.owner_id
            assert_equal "ORGANIZATION", metadata.owner_type

            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: metadata.repository_id)
              end
            end

            assert_equal 0, metadata.reload.organization_id
            assert_equal @user&.id, metadata.owner_id
            assert_equal "USER", metadata.owner_type
            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:metadata_updated"
            ]
          end

          test "updates metadata repository name for legit repository" do
            repo = create(:repository, owner: @user)
            new_name = "hahaha"
            metadata = create(:security_overview_analytics_repository, repository: repo)
            metadata.repository.update(name: new_name)
            refute_equal new_name, metadata.reload.name

            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: metadata.repository_id)
              end
            end

            assert_equal new_name, metadata.reload.name
            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:metadata_updated"
            ]
          end

          test "updates metadata repository visibility for legit repository" do
            repo = create(:repository, owner: @user)
            metadata = create(:security_overview_analytics_repository, repository: repo)

            new_visibility = "private"
            repo.set_visibility(actor: @user, visibility: new_visibility)
            refute_equal new_visibility, metadata.reload.visibility

            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: metadata.repository_id)
              end
            end

            assert_equal new_visibility, metadata.reload.visibility
            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:metadata_updated"
            ]
          end

          test "updates metadata repository archived for legit repository" do
            repo = create(:repository, owner: @user)
            metadata = create(:security_overview_analytics_repository, repository: repo)
            metadata.repository.set_archived
            refute metadata.reload.archived

            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: metadata.repository_id)
              end
            end

            assert metadata.reload.archived
            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:metadata_updated"
            ]
          end

          test "updates metadata repository pushed_at for legit repository" do
            repo = create(:repository, owner: @user)
            new_pushed_at = Time.current
            metadata = create(:security_overview_analytics_repository, repository: repo)
            metadata.repository.update(pushed_at: new_pushed_at)
            refute_equal new_pushed_at, metadata.reload.pushed_at

            perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: metadata.repository_id)
              end
            end
            assert_equal new_pushed_at&.to_i, metadata.reload.pushed_at&.to_i
            assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
              "remediation:metadata_updated"
            ]
          end

          test "updates metadata event_time when updates the record" do
            repo = create(:repository, owner: @user)
            metadata = create(:security_overview_analytics_repository, repository: repo)

            assert_changes(
              -> { metadata.reload.event_time }
            ) do
              perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
                assert_nothing_raised do
                  RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: metadata.repository_id)
                end
              end
              assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
                "remediation:metadata_updated"
              ]
            end
          end

          test "updates metadata updated_at when updates the record" do
            repo = create(:repository, owner: @user)
            metadata = create(:security_overview_analytics_repository, repository: repo)

            assert_changes(
              -> { metadata.reload.updated_at }
            ) do
              perform_enqueued_jobs only: RepositoryMetadataDeviationRemediationJob do
                assert_nothing_raised do
                  RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: metadata.repository_id)
                end
              end
              assert_dogstats_increment 1, "security_overview_analytics.repository_metadata_deviation_remediation.completed", tags: [
                "remediation:metadata_updated"
              ]
            end
          end
        end
      end

      context "hash lock" do
        test "does not allow concurrent jobs for the same input" do
          org = create(:organization)
          repo = create(:repository, owner: org)
          assert_enqueued_jobs 2, only: RepositoryMetadataDeviationRemediationJob do
            RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repo.id)
            RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repo.id)
            RepositoryMetadataDeviationRemediationJob.perform_later(session_id: "hahaha", repository_id: repo.id)
          end
        end
      end
    end
  end
end
