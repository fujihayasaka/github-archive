# typed: ignore
# frozen_string_literal: true

require "test_helper"

if GitHub.choose_commit_email_enabled?
  class AuthorEmailsDependencyTest < GitHub::TestCase
    include PullRequestSynchronizationTestHelpers

    fixtures do
      @user = create :user
      @primary_email = @user.emails.primary.first
      @primary_email.verify!
      @user_repo = create :repository, owner: @user
    end

    setup do
      example_repo :pull_request_source, @user_repo
      @user_repo_pull = PullRequest.create_for!(
        @user_repo,
        title: "blah",
        body: "blah",
        user: @user,
        base: "master",
        head: "master-forward-2",
      )

      @head_ref = @user_repo_pull.head_repository.heads.find(@user_repo_pull.head_ref)

      Spokesd.enable_spokesd
    end

    context "when the user only has one email" do
      test "author_emails returns empty array" do
        assert_empty @user.author_emails
      end

      test "default_author_email returns nil for user repo" do
        assert_nil @user.default_author_email(@user_repo, @user_repo_pull)
      end
    end

    context "when the user has more than one email" do
      test "author_emails returns both emails" do
        second_email = @user.add_email "notifications@example.com"
        second_email.verify!

        results = @user.author_emails
        assert_includes results, @primary_email.email
        assert_includes results, second_email.email
      end

      test "default_author_email returns primary email in all contexts" do
        second_email = @user.add_email "notifications@example.com"
        second_email.verify!

        assert_equal @primary_email.email, @user.default_author_email(@user_repo, @user_repo_pull.head_sha)
      end
    end

    context "but email privacy is enabled" do
      test "author_emails returns empty array" do
        second_email = create(:user_email, user: @user)
        second_email.verify!
        @user.primary_user_email.toggle_visibility
        assert @user.primary_user_email.private?

        assert_empty @user.author_emails
      end

      test "default_author_email returns nil" do
        second_email = create(:user_email, user: @user)
        second_email.verify!
        @user.primary_user_email.toggle_visibility
        assert @user.primary_user_email.private?

        assert_nil @user.default_author_email(@user_repo, @user_repo_pull.head_sha)
      end
    end

    context "caching default_author_email" do
      test "determines new default if there is no cached value" do
        new_email = @user.add_email("new@example.com")
        new_email.verify!
        new_email = new_email.email
        assert_equal @primary_email.email, @user.default_author_email(@user_repo, @user_repo_pull.head_sha)

        cache_key = @user.default_author_email_cache_key(@user_repo)
        Users::Kv.store.set(cache_key, @primary_email.email)

        metadata = {
          message: "making a change",
          committer: @user,
          author: { name: "a person", email: new_email },
        }
        with_enqueued_pr_sync_jobs do
          @head_ref.append_commit(metadata, @user) do |files|
            files.add("README.txt", "something else")
          end
        end
        create(:commit_contribution, :with_summaries, repository: @user_repo, user: @user, committed_date: Time.now.to_date)
        @user_repo_pull.reload # reload to include the new commit that was just added

        # The cache hasn't been updated so we still return the old value
        refute_equal new_email, @user.default_author_email(@user_repo, @user_repo_pull.head_sha)

        cache_key = @user.default_author_email_cache_key(@user_repo)
        Users::Kv.store.del(cache_key) # clear the cache

        # We determine the new default email because the cache has been cleared
        assert_equal new_email, @user.default_author_email(@user_repo, @user_repo_pull.head_sha)
      end

      test "determines new default if the user removed the default" do
        new_email = @user.add_email("new@example.com")
        new_email.verify!
        new_email = new_email.email
        another_email = @user.add_email("another_email@example.com")
        another_email.verify!

        assert_equal @primary_email.email, @user.default_author_email(@user_repo, @user_repo_pull.head_sha)

        cache_key = @user.default_author_email_cache_key(@user_repo)
        Users::Kv.store.set(cache_key, @primary_email.email)

        metadata = {
          message: "making a change",
          committer: @user,
          author: { name: "a person", email: new_email },
        }
        with_enqueued_pr_sync_jobs do
          @head_ref.append_commit(metadata, @user) do |files|
            files.add("README.txt", "something else")
          end
        end
        create(:commit_contribution, :with_summaries, repository: @user_repo, user: @user, committed_date: Time.now.to_date)
        @user_repo_pull.reload # reload to include the new commit that was just added

        # Emails haven't been changed so the cache hasn't been updated
        refute_equal new_email, @user.default_author_email(@user_repo, @user_repo_pull.head_sha)

        # If we remove the default email from the user, the cache will update
        @user.primary_user_email.destroy
        @user.reload
        assert_equal new_email, @user.default_author_email(@user_repo, @user_repo_pull.head_sha)
      end
    end

    test "only checks for emails used in default branch and current pull request branch" do
      new_email = @user.add_email("new@example.com")
      new_email.verify!
      new_email = new_email.email
      assert_equal @primary_email.email, @user.default_author_email(@user_repo, @user_repo_pull.head_sha)

      # Setting up a PR on a new branch
      metadata = {
        message: "making a change",
        committer: @user,
      }
      parent = @user_repo.ref_to_sha("master")
      commit = @user_repo.commits.create(metadata, parent) do |files|
        files.add("diffstat_test_1", "two\nlines\n")
      end
      ref = @user_repo.heads.create("new-topic-branch", commit, @user)
      new_branch_pull = PullRequest.create_for!(
        @user_repo,
        title: "blah",
        body: "blah",
        user: @user,
        base: "master",
        head: "new-topic-branch",
      )
      create(:commit_contribution, :with_summaries, repository: @user_repo, user: @user, committed_date: Time.now.to_date)
      assert_equal @primary_email.email, @user.default_author_email(@user_repo, new_branch_pull.head_sha)

      # Using a new email in the new branch
      metadata = {
        message: "making a change",
        committer: @user,
        author: { name: "a person", email: new_email },
      }
      with_enqueued_pr_sync_jobs do
        ref.append_commit(metadata, @user) do |files|
          files.add("README.txt", "something else")
        end
      end
      new_branch_pull.reload

      # The default email for this PR hasn't changed because:
      #   - we didn't commit with a new email in the default branch
      #   - we didn't commit with a new email in the branch for this PR
      assert_equal @primary_email.email, @user.default_author_email(@user_repo, @user_repo_pull.head_sha)

      # The default email for this PR has changed because we used a new email in its branch
      assert_equal new_email, @user.default_author_email(@user_repo, new_branch_pull.head_sha)

      perform_enqueued_jobs(only: PullRequestOrchestrationJob) do
        PullRequests::Merge.call(
          pull_request: new_branch_pull,
          user: @user,
          method: :merge,
          commit_author_email: new_email,
        )
      end

      # Now that master has a new email from this user, all branches will use it as the default
      assert_equal new_email, @user.default_author_email(@user_repo, @user_repo_pull.head_sha)
    end

    test "after committing with another email in that repo, default_author_email returns that one" do
      second_email = create(:user_email, user: @user)
      second_email.verify!
      second_email = second_email.email

      # the primary email is the default since the user is not a contributor yet
      assert_equal @primary_email.email, @user.default_author_email(@user_repo, @user_repo_pull.head_sha)

      metadata = {
        message: "making a change",
        committer: @user,
        author: { name: "a person", email: second_email },
      }
      with_enqueued_pr_sync_jobs do
        @head_ref.append_commit(metadata, @user) do |files|
          files.add("README.txt", "something else")
        end
      end
      create(:commit_contribution, :with_summaries, repository: @user_repo, user: @user, committed_date: Time.now.to_date)
      @user_repo_pull.reload # reload to include the new commit that was just added

      # Unset the default_author_email cache
      cache_key = @user.default_author_email_cache_key(@user_repo)
      Users::Kv.store.del(cache_key)
      # the commit email is the default now that the user has made a commit with it
      assert_equal second_email, @user.default_author_email(@user_repo, @user_repo_pull.head_sha)
      refute_equal @primary_email.email, second_email

      # but the primary email is still the default in another repo
      assert_equal @primary_email.email, @user.default_author_email(create :repository, nil)
    end

    test "default author email should differ for each repository" do
      cache_key = @user.default_author_email_cache_key(@user_repo)
      Users::Kv.store.set(cache_key, @primary_email.email)

      second_email = create(:user_email, user: @user)
      second_email.verify!
      second_email = second_email.email

      work_repo = create(:repository, owner: @user, from_example: :pull_request_source)
      work_repo_pull = PullRequest.create_for!(
        work_repo,
        title: "blah",
        body: "blah",
        user: @user,
        base: "master",
        head: "master-forward-2",
      )

      metadata = {
        message: "making a change",
        committer: @user,
        author: { name: "a person", email: second_email },
      }

      head_ref = work_repo_pull.head_repository.heads.find(work_repo_pull.head_ref)

      with_enqueued_pr_sync_jobs do        head_ref.append_commit(metadata, @user) do |files|
                                             files.add("README.txt", "something else")
                                           end
      end
      create(:commit_contribution, :with_summaries, repository: work_repo, user: @user, committed_date: Time.now.to_date)
      work_repo_pull.reload # reload to include the new commit that was just added

      assert_equal @primary_email.email, @user.default_author_email(@user_repo)
      assert_equal second_email, @user.default_author_email(work_repo, work_repo_pull.head_sha)
    end
  end
else
  class ChooseCommitEmailIsDisabledTest < GitHub::TestCase
    fixtures do
      @user = create :user
      @primary_email = @user.emails.primary.first.email
      @notification_email = create(:user_email, user: @user).email
      @user.emails.map(&:verify!)

      @user_repo = create :repository, owner: @user
    end

    test "author_emails returns empty array" do
      assert_empty @user.author_emails
    end

    test "default_author_email returns nil" do
      assert_nil @user.default_author_email(@user_repo, nil)
    end
  end
end

# Requires an @owner ivar to be set (and @business, which can be nil)
module UserFindByEmailSharedTests
  def test_find_by_email_returns_a_user_if_the_email_matches_with_business
    assert_equal @owner, User.find_by_email("owner@example.com", business: @business)
  end

  def test_find_by_email_works_or_breaks_without_a_business
    user = User.find_by_email("owner@example.com")
    if @owner.is_enterprise_managed?
      assert_nil user
    else
      assert_equal @owner, user
    end
  end

  def test_non_emu_business_does_not_change_results
    business = create(:business)
    user = User.find_by_email("owner@example.com", business: business)
    if @owner.is_enterprise_managed?
      assert_nil user
    else
      assert_equal @owner, user
    end
  end

  def test_returns_a_bot_if_the_email_matches_a_bot_login
    integration = create(:integration, name: "simple-ci")
    bot = integration.bot
    email = "simple-ci[bot]@users.noreply.github.com"

    assert_equal bot, User.find_by_emails([email], business: @business)[email]
  end

  def test_find_by_emails_with_business_returns_a_hash_mapping_email_addresses_to_users
    assert_equal({ "owner@example.com" => @owner }, User.find_by_emails_with_business({ @business => ["owner@example.com"] }))
  end

  def test_returns_a_hash_mapping_email_addresses_to_users
    assert_equal({ "owner@example.com" => @owner }, User.find_by_emails(["owner@example.com"], business: @business))
  end

  def test_will_not_return_a_user_for_an_email_address_that_does_not_exist
    users = User.find_by_emails("foo@bar.com", business: @business)
    assert_nil users["foo@bar.com"]
  end
end

class UserFindByEmailTest < GitHub::TestCase
  include UserFindByEmailSharedTests
  class FakeCommit < Struct.new(:author_email)
  end

  fixtures do
    @owner = create(:user, login: "owner", email: "owner@example.com", plan: "medium")
    @business = nil
    @staffer = create(:staff_admin_user, login: "staffer", plan: "medium", email: "staffer@example.com")
  end

  context ".find_by_emails" do
    test "finds users from emails" do
      @user2 = create(:user)
      emails = { @owner => %w(abc@def.com), @user2 => %w(abc2@def.com abc3@def.com) }
      emails.each_pair do |u, ems|
        ems.each do |email|
          UserEmail.create! user: u, email: email
        end
      end

      hash = User.find_by_emails emails.values.flatten
      assert_equal 3, hash.size
      emails.each_pair do |u, ems|
        ems.each do |email|
          assert_equal u, hash[email]
        end
      end

      commits = []
      emails.each_pair do |_u, ems|
        ems.each do |email|
          commits << FakeCommit.new(email)
        end
      end

      assert_equal hash, User.find_by_commits(commits, :author)
    end

    test "works with weirdly cased emails/logins" do
      upcaser = create(:user, login: "Upcaser")

      users_and_emails = [
        [upcaser, "Upcaser@users.noreply.github.com"],
        [upcaser, "UpcaSer@users.noreply.github.com"],
        [upcaser, "upcaser@users.noreply.github.com"],
      ]

      users_and_emails.each do |user, email|
        expected = { email.downcase => user }
        actual = User.find_by_emails(email)
        assert_equal(expected, actual)
      end
    end

    test "will return a user under two email addresses if aliases are passed" do
      create(:user_email, user: @staffer, email: "chris@github.com")
      users = {
        @staffer.email     => @staffer,
        "chris@github.com" => @staffer,
      }
      assert_equal users, User.find_by_emails([@staffer.email, "chris@github.com"])
    end

    test "will not return a user for a stealth email address containing a nonexistent user id" do
      stealth1 = StealthEmail.new(@staffer)
      @staffer.delete
      still_here = create(:user)
      stealth2 = StealthEmail.new(still_here)

      users = { stealth2.email => still_here }
      assert_equal users, User.find_by_emails([stealth1.email, stealth2.email])
    end

    test "it will not return an organization for a stealth email address" do
      org = create(:organization)
      org_stealth_email = "#{org.id}+#{org.name}@#{GitHub.stealth_email_host_name}"
      users = User.find_by_emails(org_stealth_email)
      assert_nil users[org_stealth_email]
    end

    test "it does not blow up when a user has a ? in their email address" do
      begin
        User.find_by_emails(["?@?"])
        assert true
      rescue ActiveRecord::PreparedStatementInvalid
        flunk "? was treated as a bind variable"
      end
    end

    test "it can find a user by stealth email" do
      stealth = StealthEmail.new(@staffer)
      assert_equal({ stealth.email => @staffer }, User.find_by_emails([stealth.email]))
    end

    test "it sets the user email state for stealth email" do
      stealth = StealthEmail.new(@staffer)
      user_email_results = User.find_by_emails([stealth.email])
      assert_equal user_email_results[stealth.email][:user_email_state], "verified"
    end

    test "it can find a user by stealth email after login change" do
      stealth = StealthEmail.new(@staffer)
      @staffer.update_attribute(:login, "newlogin")
      results = User.find_by_emails([stealth.email])
      assert_equal({ stealth.email => @staffer }, results)
      assert_equal(results[stealth.email].user_email_state, "verified")
    end

    test "it can find a user with old style stealth email" do
      stealth = StealthEmail.new(@staffer)
      stealth.save!
      email = UserEmail.where(email: stealth.email).first
      email.update_column(:email, "staffer@users.noreply.github.com")

      assert_equal({ email.to_s => @staffer }, User.find_by_emails([email.to_s]))
    end

    test "it can find a user with old style stealth email that has new stealth email" do
      stealth_email = "#{@staffer.login}@#{GitHub.stealth_email_host_name}"
      stealth = StealthEmail.new(@staffer)
      assert_equal({ stealth_email => @staffer }, User.find_by_emails([stealth_email]))
    end

    test "it returns the user for both an old style and new stealth email" do
      old_stealth_email = "#{@staffer.login}@#{GitHub.stealth_email_host_name}"
      new_stealth_email = "#{@staffer.id}+#{@staffer.login}@#{GitHub.stealth_email_host_name}"

      # enable email privacy with new stealth email format
      @staffer.primary_user_email.toggle_visibility

      expected = { new_stealth_email => @staffer, old_stealth_email => @staffer }
      assert_equal(expected, User.find_by_emails([new_stealth_email, old_stealth_email]))
    end

    test "can include users with private profiles" do
      @staffer.update!(private_profile: true)

      expected = { @staffer.email => @staffer }
      assert_equal(expected, User.find_by_emails([@staffer.email], skip_private_profiles: false))
    end

    test "can skip users with private profiles" do
      @staffer.update!(private_profile: true)

      assert_empty User.find_by_emails([@staffer.email], skip_private_profiles: true)
    end
  end

  context ".find_by_email" do
    test "for an unknown user" do
      assert_nil User.find_by_email("unknown@example.com")
    end

    test "can be found by email" do
      assert_equal @staffer, User.find_by_email(@staffer.email)
    end

    test "returns a Bot if the email matches a Bot login" do
      integration = create(:integration, name: "simple-ci")
      bot = integration.bot
      email = "simple-ci[bot]@users.noreply.github.com"

      assert_equal bot, User.find_by_email(email)
    end

    test "returns a User if the email passed in is a new stealth email" do
      user = create(:user)
      user.emails.first.toggle_visibility

      assert_equal user, User.find_by_email("#{user.id}+#{user.login}@#{GitHub.stealth_email_host_name}")
    end

    test "returns a User if the email passed in is an old stealth email" do
      user = create(:user)
      user.emails.first.toggle_visibility

      assert_equal user, User.find_by_email("#{user.login}@#{GitHub.stealth_email_host_name}")
    end

    test "returns a User if the email passed in is a new stealth email with different login" do
      user = create(:user)
      user.emails.first.toggle_visibility

      assert_equal user, User.find_by_email("#{user.id}+butts@#{GitHub.stealth_email_host_name}")
    end
  end
end

class EmuUserFindByEmailTest < GitHub::TestCase
  include UserFindByEmailSharedTests

  fixtures do
    @owner = create(:emu, login: "owner", email: "owner@example.com")
    @business = @owner.enterprise_managed_business
  end

  test "returns a User if the email passed in is a new stealth email with different login and in an emu environment" do
    user = create(:user)
    user.emails.first.toggle_visibility
    user_email = "#{user.id}+butts@#{GitHub.stealth_email_host_name}"

    assert_equal user, User.find_by_emails([user_email], business: @business)[user_email]
  end

end unless GitHub.single_business_environment?
