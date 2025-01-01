# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class TestFilter < ::ConditionalAccess::Filter
  include ConditionalAccess::Policy::TwoFactorAuthn
  include ConditionalAccess::Policy::SAML
  include ConditionalAccess::Policy::IpAllowlist

  attr_reader :user

  def initialize(callback, user)
    @user = user
    super(callback)
  end

  def conditional_access_policies
    [:ip_allowlist, :saml, :two_factor]
  end

  def location
    :test
  end

  def anonymous?
    @user.nil?
  end

  def actor
    @user
  end

  def actor_ip
    "127.0.0.1"
  end
end

class PullRequestCloseIssueReferenceDependencyTest < GitHub::TestCase
  fixtures do
    Spokesd.enable_spokesd
    @owner = create(:user)
    @org = create(:organization, admin: @owner)
    @two_factor_org = create :business_plus_org, admin: @owner
    @another_org = create(:organization)

    @user_repo_one = create :private_repository, owner: @owner
    @user_repo_two = create :private_repository, owner: @owner


    @org_repo_one = create :private_repository, owner: @org
    @org_repo_two = create :private_repository, owner: @org
    @two_factor_repo = create :private_repository, owner: @two_factor_org

    @another_org_repo = create :private_repository, owner: @another_org

    example_repo_snapshot
  end

  setup do
    Spokesd.enable_spokesd
    example_repo_restore
  end

  def build_pr(repo:, owner:, base_ref_name: "master", branch_name: SecureRandom.uuid)
    master_ref = repo.heads.find_or_build("master")
    append_dummy_commit(master_ref)

    base_ref = if base_ref_name == "master"
      master_ref
    else
      repo.heads.create(base_ref_name, master_ref.target_oid, owner)
    end

    append_dummy_commit(base_ref)

    open_ref = repo.heads.create(branch_name, base_ref.target, owner)
    append_dummy_commit(open_ref)

    create(:pull_request, build_pull_attrs(repo: repo, user: owner).merge(head_ref: branch_name, base_ref: base_ref_name))
  end

  def append_dummy_commit(ref)
    repo = ref.repository
    ref.append_commit({ message: "a commit", committer: repo.owner }, repo.owner) do |files|
      files.add("file001-#{ref}", "foo")
    end
  end

  def build_pull_attrs(repo:, user:)
    {
      repository: repo,
      base_repository: repo,
      base_user: user,
      head_repository: repo,
      head_user: user,
      user: user,
    }
  end

  context "#closable_issues" do
    test "returns empty list when repository no longer exists" do
      pull = build_pr(repo: @org_repo_one, owner: @owner)
      other_issue = create(:issue, repository: @org_repo_one)

      pull.issue.update_attribute(:body, "Fixes ##{other_issue.number}")
      @org_repo_one.destroy
      pull.reload

      assert_empty pull.closable_issues
    end

    test "returns issue referenced by open pull request" do
      pull = build_pr(repo: @org_repo_one, owner: @owner)
      other_issue = create(:issue, repository: @org_repo_one)
      pull.issue.update_attribute(:body, "Fixes ##{other_issue.number}")
      assert_predicate pull, :open?

      assert_equal [other_issue], pull.closable_issues
    end
  end

  context ".closes scope" do
    test "includes only pull requests that say they close the given issue, by the given author" do
      collaborator = create(:user)
      @org_repo_one.add_member(collaborator)

      issue = create(:issue, repository: @org_repo_one)
      pull = build_pr(repo: @org_repo_one, owner: @owner)
      other_pull = build_pr(repo: @org_repo_one, owner: collaborator)

      create(:close_issue_reference, issue: issue, pull_request: pull)
      create(:close_issue_reference, issue: issue, pull_request: other_pull)

      result = PullRequest.closes(issue, @owner)

      assert_includes result, pull
      refute_includes result, other_pull
    end
  end

  test "deletes CloseIssueReference when destroyed" do
    ref = create(:close_issue_reference)

    assert_difference("CloseIssueReference.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { ref.pull_request.destroy }
    end

    refute CloseIssueReference.exists?(ref.id)
  end

  # The majority of test cases are covered in the resolver test
  # See test/platform/resolvers/closing_issue_references_test.rb
  context "#close_issue_references_for" do
    test "returns references the viewer can see" do
      xref = create(:close_issue_reference, actor_id: @owner.id)

      filter = TestFilter.new(self, @owner)
      result = xref.pull_request.cap_filtered_close_issue_references_for(viewer: @owner, cap_filter: filter)

      assert_same_elements [xref.issue], result
    end

    test "returns manual references the viewer can see when no manual references" do
      xref = create(:close_issue_reference, actor_id: @owner.id)

      filter = TestFilter.new(self, @owner)
      result = xref.pull_request.cap_filtered_close_issue_references_for(viewer: @owner, user_linked_only: true, cap_filter: filter)

      assert_equal 0, result.length
    end

    test "returns manual references the viewer can see" do
      xref = create(:close_issue_reference, actor_id: @owner.id, source: "manual")

      filter = TestFilter.new(self, @owner)
      result = xref.pull_request.cap_filtered_close_issue_references_for(viewer: @owner, user_linked_only: true, cap_filter: filter)

      assert_equal 1, result.length
    end

    test "does not return references the user can't access" do
      rando = create(:user)
      pr = build_pr(repo: create(:repository), owner: @owner, base_ref_name: "master", branch_name: SecureRandom.uuid)
      private_issue = create(:issue, repository: @user_repo_one)
      xref = create(:close_issue_reference, issue: private_issue, pull_request: pr, actor_id: @owner.id)

      filter = TestFilter.new(self, rando)
      result = Platform::Security::RepositoryAccess.with_viewer(rando) do
        pr.cap_filtered_close_issue_references_for(viewer: rando, cap_filter: filter)
      end

      assert_empty result
    end

    test "does not return references if two factor auth is required but not satisfied" do
      pr = build_pr(repo: @two_factor_repo, owner: @owner, base_ref_name: "master", branch_name: SecureRandom.uuid)
      private_issue = create(:issue, repository: @two_factor_repo)
      xref = create(:close_issue_reference, issue: private_issue, pull_request: pr, actor_id: @owner.id)

      filter = TestFilter.new(self, @owner)
      result = pr.cap_filtered_close_issue_references_for(viewer: @owner, cap_filter: filter)

      assert_same_elements [xref.issue], result

      @two_factor_org.enable_two_factor_required(actor: @owner)

      filter = TestFilter.new(self, @owner)
      result = pr.cap_filtered_close_issue_references_for(viewer: @owner, cap_filter: filter)

      assert_empty result
    end

    test "requires unauthorized_organization_ids argument for SAML check" do
      # ensure that the caller must past this argument
      # the resolver tests more specifically assert the correct saml authorization
      xref = create(:close_issue_reference)
      assert_raises ArgumentError do
        xref.pull_request.cap_filtered_close_issue_references_for(viewer: @owner)
      end
    end

  end

  context "when xrefed in PR body" do

    context "when xrefed issue is in the same repo" do

      test "creates close_issue_reference" do
        issue = create(:issue, repository: @user_repo_one)
        pull = build_pr(repo: @user_repo_one, owner: @owner)

        GitHub.context.push(actor_id: @owner.id)

        assert_difference "pull.close_issue_references.count", 1 do
          perform_enqueued_jobs(only: [UpdateCloseIssueReferencesJob, IssueOrchestration.job_class]) do
            pull.issue.update!(body: "Closes ##{issue.number}")
          end
        end

        assert_equal issue, pull.close_issue_references.first.issue
        assert_equal @owner.id, pull.close_issue_references.first.actor_id
      end

      test "closes xrefed issue when merged" do
        issue = create(:issue, repository: @user_repo_one)
        pull = build_pr(repo: @user_repo_one, owner: @owner)

        GitHub.context.push(actor_id: @owner.id)

        pull.issue.update!(body: "Closes ##{issue.number}")

        perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { pull.merge(@owner) }
        assert issue.reload.closed?
      end

      test "does not close xrefed issue if removed from body and close_issue_reference record still exists" do
        issue = create(:issue, repository: @user_repo_one)
        pull = build_pr(repo: @user_repo_one, owner: @owner)

        GitHub.context.push(actor_id: @owner.id)

        perform_enqueued_jobs(only: [UpdateCloseIssueReferencesJob, IssueOrchestration.job_class]) do
          pull.issue.update!(body: "Closes ##{issue.number}")
        end

        pull.issue.update!(body: "Bloop!")

        # closing reference still exists because background job hasn't removed it yet
        assert_equal 1, pull.close_issue_references.count

        perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { pull.merge(@owner) }

        assert issue.reload.open?
      end

      test "does not close xrefed issue if PR not against the default base branch" do
        repo = create :private_repository, owner: @owner
        issue = create(:issue, repository: repo)
        pull = build_pr(repo: repo, owner: @owner, base_ref_name: "staging")

        GitHub.context.push(actor_id: @owner.id)

        pull.issue.update!(body: "Closes ##{issue.number}")

        # closing reference is not created because it's not targeted against the base branch
        assert_empty pull.reload.close_issue_references

        perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { pull.merge(@owner) }
        refute_predicate issue.reload, :closed?
      end
    end

    context "when xrefed issue is in a different repo owned by the same user" do

      test "creates close_issue_reference" do
        issue = create(:issue, repository: @user_repo_two)
        pull = build_pr(repo: @user_repo_one, owner: @owner)

        GitHub.context.push(actor_id: @owner.id)

        assert_difference "pull.close_issue_references.count", 1 do
          perform_enqueued_jobs(only: [UpdateCloseIssueReferencesJob, IssueOrchestration.job_class]) do
            pull.issue.update!(body: "Closes #{@user_repo_two.nwo}##{issue.number}")
          end
        end

        assert_equal issue, pull.close_issue_references.first.issue
      end

      test "closes xrefed issue when merged" do
        issue = create(:issue, repository: @user_repo_two)
        pull = build_pr(repo: @user_repo_one, owner: @owner)

        GitHub.context.push(actor_id: @owner.id)

        pull.issue.update!(body: "Closes #{@user_repo_two.nwo}##{issue.number}")

        perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { pull.merge(@owner) }
        assert issue.reload.closed?
      end

      test "does not close xrefed issue if merger does not have permissions" do
        rando = create(:user)
        @user_repo_one.add_member(rando)

        issue = create(:issue, repository: @user_repo_two)
        pull = build_pr(repo: @user_repo_one, owner: @owner)

        GitHub.context.push(actor_id: @owner.id)

        perform_enqueued_jobs(only: [UpdateCloseIssueReferencesJob, IssueOrchestration.job_class]) do
          pull.issue.update!(body: "Closes #{@user_repo_two.nwo}##{issue.number}")
        end

        refute_empty pull.close_issue_references

        perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { pull.merge(rando) }
        assert pull.reload.merged?
        refute issue.closable_by?(rando)
        assert issue.reload.open?
      end

    end

    context "when xrefed issue is in a different repo owned by the same org" do

      test "creates close_issue_reference" do
        issue = create(:issue, repository: @org_repo_two)
        pull = build_pr(repo: @org_repo_one, owner: @owner)

        GitHub.context.push(actor_id: @owner.id)

        assert_difference "pull.close_issue_references.count", 1 do
          perform_enqueued_jobs(only: [UpdateCloseIssueReferencesJob, IssueOrchestration.job_class]) do
            pull.issue.update!(body: "Closes #{@org_repo_two.nwo}##{issue.number}")
          end
        end

        assert_equal issue, pull.close_issue_references.first.issue
      end

      test "closes xrefed issue when merged" do
        issue = create(:issue, repository: @org_repo_two)
        pull = build_pr(repo: @org_repo_one, owner: @owner)

        GitHub.context.push(actor_id: @owner.id)

        pull.issue.update!(body: "Closes #{@org_repo_two.nwo}##{issue.number}")

        perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { pull.merge(@owner) }
        assert issue.reload.closed?
      end

      test "does not close xrefed issue if merger does not have permissions" do
        rando = create(:user)
        @user_repo_one.add_member(rando)

        issue = create(:issue, repository: @org_repo_two)
        pull = build_pr(repo: @org_repo_one, owner: @owner)

        GitHub.context.push(actor_id: @owner.id)

        perform_enqueued_jobs(only: [UpdateCloseIssueReferencesJob, IssueOrchestration.job_class]) do
          pull.issue.update!(body: "Closes #{@org_repo_two.nwo}##{issue.number}")
        end

        refute_empty pull.close_issue_references

        perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { pull.merge(rando) }

        assert pull.reload.merged?
        refute issue.closable_by?(rando)
        assert issue.reload.open?
      end

      test "app with issues:write permissions closes xrefed issue when merged" do
        installation = make_integration_installation(
          target: @org,
          repositories: [@org_repo_one, @org_repo_two],
          permissions: {
            "metadata" => :read,
            "issues" => :write,
            "pull_requests" => :write
          }
        )
        issue = create(:issue, repository: @org_repo_two)
        pull = build_pr(repo: @org_repo_one, owner: @owner)

        GitHub.context.push(actor_id: installation.bot.id)

        pull.issue.update!(body: "Closes #{@org_repo_two.nwo}##{issue.number}")

        perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { pull.merge(installation.bot) }
        assert issue.reload.closed?
      end

      test "app with issues:read permissions cannot close xrefed issue when merged" do
        installation = make_integration_installation(
          target: @org,
          repositories: [@org_repo_one, @org_repo_two],
          permissions: {
            "metadata" => :read,
            "issues" => :read,
            "pull_requests" => :write
          }
        )
        issue = create(:issue, repository: @org_repo_two)
        pull = build_pr(repo: @org_repo_one, owner: @owner)

        GitHub.context.push(actor_id: installation.bot.id)

        pull.issue.update!(body: "Closes #{@org_repo_two.nwo}##{issue.number}")

        perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { pull.merge(installation.bot) }
        refute issue.reload.closed?
      end

      test "app with issues:write cannot close xrefed issue in repo where not installed when PR merged" do
        user_with_installation = create(:user)
        random_user = create(:user)

        repo_with_installation = create :repository, owner: user_with_installation
        random_user_repo = create :repository, owner: random_user

        installation = make_integration_installation(
          target: user_with_installation,
          permissions: {
                  "metadata" => :read,
                  "issues" => :write,
                  "pull_requests" => :write
          }
        )
        issue = create(:issue, repository: random_user_repo)
        pull = build_pr(repo: repo_with_installation, owner: user_with_installation)

        GitHub.context.push(actor_id: installation.bot.id)

        pull.issue.update!(body: "Closes #{random_user_repo.nwo}##{issue.number}")

        perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { pull.merge(installation.bot) }
        refute issue.reload.closed?
      end
    end

    context "when xrefed issue is in a repo owned by a different owner" do

      test "creates close_issue_reference if author has permissions" do
        @another_org_repo.add_member(@owner)
        issue = create(:issue, repository: @another_org_repo)
        pull = build_pr(repo: @org_repo_one, owner: @owner)

        GitHub.context.push(actor_id: @owner.id)

        assert_difference "pull.close_issue_references.count", 1 do
          perform_enqueued_jobs(only: [UpdateCloseIssueReferencesJob, IssueOrchestration.job_class]) do
            pull.issue.update!(body: "Closes #{@another_org_repo.nwo}##{issue.number}")
          end
        end

        assert_equal issue, pull.close_issue_references.first.issue
        assert_equal @owner.id, pull.close_issue_references.first.actor_id
      end

      test "does not create close_issue_reference if author does not have access" do
        issue = create(:issue, repository: @another_org_repo)
        pull = build_pr(repo: @org_repo_one, owner: @owner)

        GitHub.context.push(actor_id: @owner.id)

        assert_no_difference "pull.close_issue_references.count" do
          pull.issue.update!(body: "Closes #{@another_org_repo.nwo}##{issue.number}")
        end
      end

      test "does not create close_issue_reference if editor does not have access" do
        editor = create(:user)
        @org_repo_one.add_member(editor)
        @another_org_repo.add_member(@owner) # owner has access to other repo, but editor does not

        issue = create(:issue, repository: @another_org_repo)
        pull = build_pr(repo: @org_repo_one, owner: @owner)

        GitHub.context.push(actor_id: editor.id)

        assert_no_difference "pull.close_issue_references.count" do
          pull.issue.update_body("Closes #{@another_org_repo.nwo}##{issue.number}", editor)
        end
      end

      test "does not remove existing close_issue_reference when edited if editor does not have access" do
        editor = create(:user)
        @org_repo_one.add_member(editor)
        @another_org_repo.add_member(@owner) # owner has access to other repo, but editor does not

        issue = create(:issue, repository: @another_org_repo)
        pull = build_pr(repo: @org_repo_one, owner: @owner)

        GitHub.context.push(actor_id: @owner.id)

        # Owner edits PR to create reference
        assert_difference "pull.close_issue_references.count", 1 do
          perform_enqueued_jobs(only: [UpdateCloseIssueReferencesJob, IssueOrchestration.job_class]) do
            pull.issue.update_body("Closes #{@another_org_repo.nwo}##{issue.number}", @owner)
          end
        end

        GitHub.context.push(actor_id: editor.id)

        # Editor edits PR to add some additional info, but leaves closing keyword intact
        assert_no_difference "pull.close_issue_references.count" do
          pull.issue.update_body("Closes #{@another_org_repo.nwo}##{issue.number} and makes our PM happy", editor)
        end

        assert_equal issue, pull.close_issue_references.first.issue
      end

      test "creates close_issue_reference if editor has access" do
        editor = create(:user)
        @org_repo_one.add_member(editor)
        @another_org_repo.add_member(editor)
        @another_org_repo.add_member(@owner)

        issue = create(:issue, repository: @another_org_repo)
        pull = build_pr(repo: @org_repo_one, owner: @owner)

        GitHub.context.push(actor_id: editor.id)

        assert_difference "pull.close_issue_references.count", 1 do
          perform_enqueued_jobs(only: [UpdateCloseIssueReferencesJob, IssueOrchestration.job_class]) do
            pull.issue.update_body("Closes #{@another_org_repo.nwo}##{issue.number}", editor)
          end
        end

        assert_equal issue, pull.close_issue_references.first.issue
      end

      test "closes xrefed issue when merged if user has been given permission" do
        @another_org_repo.add_member(@owner)
        issue = create(:issue, repository: @another_org_repo)
        pull = build_pr(repo: @org_repo_one, owner: @owner)

        GitHub.context.push(actor_id: @owner.id)

        pull.issue.update!(body: "Closes #{@another_org_repo.nwo}##{issue.number}")

        perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { pull.merge(@owner) }
        assert pull.reload.merged?
        assert issue.closable_by?(@owner)
        assert issue.reload.closed?
      end

      test "does not close xrefed issue if merger does not have permissions" do
        issue = create(:issue, repository: @another_org_repo)
        pull = build_pr(repo: @org_repo_one, owner: @owner)

        GitHub.context.push(actor_id: @owner.id)

        pull.issue.update!(body: "Closes #{@another_org_repo.nwo}##{issue.number}")

        perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { pull.merge(@owner) }
        assert pull.reload.merged?
        refute issue.closable_by?(@owner)
        assert issue.reload.open?
      end
    end

  end

  context "when manually cross referenced" do

    context "when xrefed issue is in the same repo" do
      test "closes xrefed issue when merged" do
        issue = create(:issue, repository: @user_repo_one)
        pull = build_pr(repo: @user_repo_one, owner: @owner)

        create(:manual_close_issue_reference, issue: issue, pull_request: pull)

        perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { pull.merge(@owner) }
        assert issue.reload.closed?
      end

      test "does not close xrefed issue if PR not against the default base branch" do
        issue = create(:issue, repository: @user_repo_one)
        pull = build_pr(repo: @user_repo_one, owner: @owner, base_ref_name: "cooler_(b)ranch_#{SecureRandom.uuid}")

        create(:manual_close_issue_reference, issue: issue, pull_request: pull)

        perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { pull.merge(@owner) }
        refute_predicate issue.reload, :closed?
      end
    end

    context "when xrefed issue is in a different repo owned by the same user" do

      test "closes xrefed issue when merged" do
        issue = create(:issue, repository: @user_repo_two)
        pull = build_pr(repo: @user_repo_one, owner: @owner)

        create(:manual_close_issue_reference, issue: issue, pull_request: pull)

        perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { pull.merge(@owner) }
        assert issue.reload.closed?
      end

      test "does not close xrefed issue if merger does not have permissions" do
        rando = create(:user)
        @user_repo_one.add_member(rando)

        issue = create(:issue, repository: @user_repo_two)
        pull = build_pr(repo: @user_repo_one, owner: @owner)

        create(:manual_close_issue_reference, issue: issue, pull_request: pull)

        perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { pull.merge(rando) }
        assert pull.reload.merged?
        refute issue.closable_by?(rando)
        assert issue.reload.open?
      end

    end

    context "when xrefed issue is in a different repo owned by the same org" do

      test "closes xrefed issue when merged" do
        issue = create(:issue, repository: @org_repo_two)
        pull = build_pr(repo: @org_repo_one, owner: @owner)

        create(:manual_close_issue_reference, issue: issue, pull_request: pull)

        perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { pull.merge(@owner) }
        assert issue.reload.closed?
      end

      test "does not close xrefed issue if merger does not have permissions" do
        rando = create(:user)
        @user_repo_one.add_member(rando)

        issue = create(:issue, repository: @org_repo_two)
        pull = build_pr(repo: @org_repo_one, owner: @owner)

        create(:manual_close_issue_reference, issue: issue, pull_request: pull)

        perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { pull.merge(rando) }
        assert pull.reload.merged?
        refute issue.closable_by?(rando)
        assert issue.reload.open?
      end

    end

  end
end
