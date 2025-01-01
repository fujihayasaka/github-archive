# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryAdvisoryDependencyTest < GitHub::TestCase
  fixtures do
    @owner = create :user
    @public_repo = create :repository, owner: @owner
    @private_repo = create :private_repository, owner: @owner
    @collab = create :user
    @private_repo.add_member(@collab)

    @advisory = create(:repository_advisory,
                        repository: @private_repo,
                        author: @owner,
                        title: "💎 Path Traversal on Default Installed Rails Application",
                        description: "**Urgent**: Vulnerability has been _disclosed_",
                        cve_id: "CVE-1900-0001",
                        severity: "moderate")
    @published_advisory = create :published_repository_advisory, repository: @private_repo
    @draft_advisory = create :draft_repository_advisory, repository: @private_repo
    @advisory.affected_products.first.update!(
      package: "my-example-package.rb",
      ecosystem: "RubyGems",
      affected_versions: "<5.1.0",
      patches: "No patches currently available.",
    )
    @advisory.add_collaborator(@collab)
    @advisory.create_comment(@collab, "A comment")
  end

  setup do
    GitHub.flipper[:advisory_db_unrestorable_repositories].disable(@private_repo)
    GitHub.flipper[:private_advisories_disabled].disable(@private_repo)
    GitHub.flipper[:innersource_advisories].disable
  end

  context "#repository_advisories" do
    context "#available_to" do
      test "defines a custom available_to finder" do
        advisories = @private_repo.repository_advisories.available_to(@collab)
        assert_includes advisories, @advisory
      end

      test "does not include drafts the collaborator does not have access to" do
        advisories = @private_repo.repository_advisories.available_to(@collab)

        assert_equal 2, advisories.length
        assert_includes advisories, @advisory
        assert_includes advisories, @published_advisory
        refute_includes advisories, @draft_advisory
      end

      test "installations with read scope on :repository_advisories get all available advisories" do
        integration = create :integration
        installation = make_integration_installation integration: integration, target: @owner, permissions: { "repository_advisories" => :read }

        advisories = @private_repo.repository_advisories.available_to(installation)

        assert_equal @private_repo.repository_advisories.count, advisories.length
        assert_includes advisories, @advisory
        assert_includes advisories, @published_advisory
        assert_includes advisories, @draft_advisory
      end

      test "installations on a private repo without read scope on :repository_advisories get no published advisories" do
        integration = create :integration
        installation = make_integration_installation integration: integration, target: @owner

        advisories = @private_repo.repository_advisories.available_to(installation)

        assert_equal 0, advisories.length
      end

      test "installations on a public repo without read scope on :repository_advisories only get published advisories" do
        public_repo = create(:public_repository)
        published_advisory = create :published_repository_advisory, repository: public_repo
        draft_advisory = create :draft_repository_advisory

        integration = create :integration
        installation = make_integration_installation integration: integration, target: public_repo.owner

        advisories = public_repo.repository_advisories.available_to(installation)

        assert_equal 1, advisories.length
        assert_includes advisories, published_advisory
        refute_includes advisories, draft_advisory
      end
    end

    context "#state" do
      test "returns advisories in a given state" do
        advisories = @private_repo.repository_advisories.state(:draft)
        assert_equal 2, advisories.length
        assert_equal [@advisory.id, @draft_advisory.id].sort, advisories.pluck(:id).sort
      end
    end

    test "when a repository is deleted and FF is enabled, mark repo as unrestorable and remove link" do
      GitHub.context.push(actor_id: @collab.id)

      advisory1 = create(:repository_advisory, repository: @private_repo, author: @collab)
      workspace_repo1 = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory1, @collab).tap(&:save!)

      parent_advisory = workspace_repo1.parent_advisory

      GitHub.flipper[:advisory_db_unrestorable_repositories].enable(@private_repo)
      workspace_repo1.remove(@admin, synchronous: true)

      refute workspace_repo1.restorable?

      workspace_repo1.reload
      assert_nil workspace_repo1.parent_advisory
      assert_nil parent_advisory.workspace_repository
    end

    test "are deleted via destroy_dependents_in_background when the repository is deleted" do
      assert_equal 3, @private_repo.repository_advisories.length

      assert_difference "RepositoryAdvisory.count", -3 do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
          @private_repo.destroy!
        end
      end
    end

    context "#advisories_enabled?" do
      if GitHub.single_or_multi_tenant_enterprise?
        test "returns false on public repos" do
          refute @public_repo.advisories_enabled?
        end

        test "returns false on private repos" do
          refute @private_repo.advisories_enabled?
        end
      else
        test "returns true on public repos" do
          assert @public_repo.advisories_enabled?
        end

        test "returns false on an exempt private repository when FF enabled" do
          GitHub.flipper[:private_advisories_disabled].enable(@private_repo)
          assert AdvisoryDB::Innersource.private_advisory_exempt_repo?(repo: @private_repo)
          refute @private_repo.advisories_enabled?
        end

        test "returns true on a private repository when FF disabled" do
          GitHub.flipper[:private_advisories_disabled].disable(@private_repo)
          assert @private_repo.advisories_enabled?
        end
      end
    end

    context "#limit_advisory_type" do
      test "returns innersource advisories" do
        GitHub.flipper[:innersource_advisories].enable
        GitHub.flipper[:private_advisories_disabled].enable
        Repository.any_instance.stubs(:innersource_advisories_enabled?).returns(true)
        3.times { create(:published_innersource_advisory, repository: @private_repo, author: @owner) }

        assert_equal 3, @private_repo.repository_advisories.limit_advisory_type(type: :innersource).length
        @private_repo.repository_advisories.limit_advisory_type(type: :innersource).each { |advisory| assert advisory.innersource? }
      end

      test "returns open source advisories" do
        clean_private_repo = create(:repository, owner: @owner)
        3.times { create(:published_repository_advisory, repository: clean_private_repo, author: @owner) }

        GitHub.flipper[:innersource_advisories].enable
        GitHub.flipper[:private_advisories_disabled].enable
        Repository.any_instance.stubs(:innersource_advisories_enabled?).returns(true)
        3.times { create(:published_innersource_advisory, repository: clean_private_repo, author: @owner) }

        assert_equal 3, clean_private_repo.repository_advisories.limit_advisory_type(type: :open_source).length
        clean_private_repo.repository_advisories.limit_advisory_type(type: :open_source).each { |advisory| assert advisory.open_source? }
      end

      test "returns open source advisories if no type is specified and innersource is disabled" do
        @private_repo.repository_advisories.limit_advisory_type.each { |advisory| assert advisory.open_source? }
      end

      test "returns innersource advisories if no type is specified and innersource is enabled" do
        GitHub.flipper[:innersource_advisories].enable
        GitHub.flipper[:private_advisories_disabled].enable
        Repository.any_instance.stubs(:innersource_advisories_enabled?).returns(true)

        @private_repo.repository_advisories.limit_advisory_type.each { |advisory| assert advisory.innersource? }
      end
    end
  end
end
