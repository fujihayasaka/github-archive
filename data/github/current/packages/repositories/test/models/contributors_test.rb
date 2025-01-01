# typed: false
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

module ContributorsSharedTests
  def test_contributors
    contributors = Contributors.new(@simple, not_computable_ids: Set.new)
    all_response = contributors.all
    assert_predicate all_response, :computed?
    assert_equal @contributors,
      all_response.value.map { |user, _count| user.login }
  end

  def test_contributors_with_merges_ignored
    repo = create(:repository, owner: @rtomayko, from_example: :pull_request_source)

    repo.default_branch = "master-merged-topic"

    contributors = Contributors.new(repo, not_computable_ids: Set.new, ignore_merge_commits: false)
    all_response = contributors.all
    assert_predicate all_response, :computed?
    assert_equal [[@rtomayko, 19]], all_response.value

    contributors = Contributors.new(repo, not_computable_ids: Set.new, ignore_merge_commits: true)
    all_response = contributors.all
    assert_predicate all_response, :computed?
    assert_equal [[@rtomayko, 17]], all_response.value
  end
end

class ContributorsTest < GitHub::TestCase
  include ContributorsSharedTests

  fixtures do
    @rtomayko = create(:user, login: "rtomayko", email: "rtomayko@gmail.com")

    @nick = create(:user, login: "nickh", email: "nickh@github.com")
    @rob = create(:user, login: "rsanheim", email: "rsanheim@gmail.com")
    @spammy_harry = create(:user, login: "spamming-all-day", spammy: true)

    @simple   = create(:repository, name: "simple", owner: @rtomayko, from_example: :simple)
    @encoding = create(:repository, name: "encoding", owner: @rtomayko, from_example: :encodings)


    @contributors = %w( nickh rsanheim )
  end

  setup do
    @simple.update_default_branch("master")
    reset_cache
  end

  test "contributors with anonymous" do
    contributors = Contributors.new(@simple, not_computable_ids: Set.new)
    all_with_anon_response = contributors.all(with_anon: true)
    assert_predicate all_with_anon_response, :computed?

    all = all_with_anon_response.value.map do |user, _count|
      user.is_a?(User) ? user.login : user[:name]
    end
    assert_includes all, "rsanheim"
    assert_includes all, "nickh"
    assert_includes all, "rick"
  end

  test "contributors does not include spammy users for a viewer", skip_enterprise: true do
    ref = @simple.heads.find("master")
    ref.append_commit({ message:  "a commit", committer:  @spammy_harry }, @spammy_harry) do |files|
      files.add("file001", "foo")
    end

    contributors = Contributors.new(@simple, not_computable_ids: Set.new)
    all_response = contributors.all(viewer: @rtomayko)

    assert_predicate all_response, :computed?
    all = all_response.value.map { |user, _count| user.is_a?(User) ? user.login : user[:name] }
    assert_includes all, "nickh"
    assert_includes all, "rsanheim"
    refute_includes all, "spamming-all-day"
  end

  test "contributors includes the spammy user when they are the viewer", skip_enterprise: true do
    ref = @simple.heads.find("master")
    ref.append_commit({ message:  "a commit", committer:  @spammy_harry }, @spammy_harry) do |files|
      files.add("file001", "foo")
    end

    contributors = Contributors.new(@simple, not_computable_ids: Set.new)
    all_response = contributors.all(viewer: @spammy_harry)

    assert_predicate all_response, :computed?
    all = all_response.value.map { |user, _count| user.is_a?(User) ? user.login : user[:name] }
    assert_includes all, "nickh"
    assert_includes all, "rsanheim"
    assert_includes all, "spamming-all-day"
  end

  test "contributors includes contributions from mixed-case legacy stealth emails" do
    user = create(:user, login: "ExampleContributor")
    ref = @simple.heads.find("master")
    author = { name: "Example Contributor", email: "ExampleContributor@#{ GitHub.stealth_email_host_name }" }
    ref.append_commit({ message:  "a commit", committer: author }, user) do |files|
      files.add("file001", "foo")
    end

    contributors = Contributors.new(@simple, not_computable_ids: Set.new)
    all_response = contributors.all

    assert_predicate all_response, :computed?
    all = all_response.value.map { |user, _count| user.is_a?(User) ? user.login : user[:name] }
    assert_includes all, user.login
  end

  test "contributors with encoding issues" do
    contributors = Contributors.new(@encoding, not_computable_ids: Set.new)
    all_response = contributors.all(with_anon: true)
    assert_predicate all_response, :computed?
    all = all_response.value.map { |user, _count| user.is_a?(User) ? user.login : user[:name] }
    assert_includes all, "unknown"
  end

  test "contributors knows when it was computed" do
    contributors = Contributors.new(@simple, not_computable_ids: Set.new)
    all_response = contributors.all
    assert_predicate all_response, :computed?
    assert_equal %w( nickh rsanheim ),
      all_response.value.map { |user, _count| user.login }
  end

  test "contributors knows when it was not computed" do
    contributors = Contributors.new(@simple, not_computable_ids: Set.new([@simple.id]))
    all_response = contributors.all
    refute_predicate all_response, :computed?
    assert_equal [], all_response.value
  end

  test "count knows when it was computed" do
    contributors = Contributors.new(@simple)
    count_response = contributors.count
    assert_predicate count_response, :computed?
    assert_equal 2, count_response.value
  end

  test "count knows when it was not computed" do
    contributors = Contributors.new(@simple, not_computable_ids: Set.new([@simple.id]))
    count_response = contributors.count
    refute_predicate count_response, :computed?
    assert_equal 0, count_response.value
  end

  test "count caches not computable sentinel value for not computable repo" do
    with_cache_enabled do
      contributors = Contributors.new(@simple, not_computable_ids: Set.new([@simple.id]))
      refute_predicate contributors.count, :computed?
      assert_equal :not_computable,
        GitHub.cache.get(contributors.count_cache_key)
    end
  end

  test "count returns not computed for cached not computable sentinel" do
    with_cache_enabled do
      contributors = Contributors.new(@simple, not_computable_ids: Set.new)
      GitHub.cache.set(contributors.count_cache_key, :not_computable)
      count_response = contributors.count
      refute_predicate count_response, :computed?
      assert_equal 0, count_response.value
    end
  end

  test "count_from_cache returns nil if uncached" do
    with_cache_enabled do
      contributors = Contributors.new(@simple, not_computable_ids: Set.new)
      assert_nil contributors.count_from_cache
    end
  end

  test "count_from_cache returns correct response if cached" do
    with_cache_enabled do
      contributors = Contributors.new(@simple, not_computable_ids: Set.new)
      GitHub.cache.set(contributors.count_cache_key, 2)
      response = contributors.count_from_cache
      assert_predicate response, :computed?
      assert_equal 2, response.value
    end
  end

  test "count_from_cache returns correct response if not_computable sentinal cached" do
    with_cache_enabled do
      contributors = Contributors.new(@simple, not_computable_ids: Set.new)
      GitHub.cache.set(contributors.count_cache_key, :not_computable)
      response = contributors.count_from_cache
      refute_predicate response, :computed?
      assert_equal 0, response.value
    end
  end

  test "shortlog knows when it was computed" do
    contributors = Contributors.new(@simple, not_computable_ids: Set.new)
    shortlog = <<-EOS
     3\trick <technoweenie@gmail.com>
     1\tNick Hengeveld <nickh@github.com>
     1\tRob Sanheim <rsanheim@gmail.com>
    EOS
    response = contributors.all
    assert_predicate response, :computed?
    assert_equal [[@nick, 1], [@rob, 1]], response.value
  end

  test "shortlog knows when it was not computed" do
    contributors = Contributors.new(@simple, not_computable_ids: Set.new([@simple.id]))
    response = contributors.all
    refute_predicate response, :computed?
    assert_equal [], response.value
  end

  [true, false].each do |mailmap|
    test "returns computed response if repository missing default_oid with mailmap=#{mailmap}" do
      @simple.update_default_branch_spokes("refs/heads/nopenothere")
      contributors = Contributors.new(@simple, not_computable_ids: Set.new, mailmap: mailmap)
      response = contributors.all
      assert_predicate response, :computed?
      assert_equal [], response.value
    end

    test "returns computed response if repository is empty, mailmap=#{mailmap}" do
      empty_repository = create(:repository, :empty)
      contributors = Contributors.new(empty_repository, not_computable_ids: Set.new, mailmap: mailmap)
      response = contributors.all
      assert_predicate response, :computed?
      assert_equal [], response.value
    end
  end

  test "shortlog handles utf-8 shortlogs" do
    shortlog = "1\trick🎉<technoweenie@gmail.com>"
    @simple.rpc.expects(:contributor_shortlog).returns(shortlog)
    contributors = Contributors.new(@simple, not_computable_ids: Set.new, mailmap: true)
    response = contributors.all
    assert_predicate response, :computed?
    assert_equal [], response.value
  end

  test "shortlog caches raw shortlog" do
    @simple.rpc.expects(:contributor_shortlog).once.returns("<fake output>")
    with_cache_enabled do
      2.times do
        contributors = Contributors.new(@simple, not_computable_ids: Set.new)
        response = contributors.all
        assert_predicate response, :computed?
        assert_equal [], response.value
      end
    end
  end

  test "shortlog is not computed on GitRPC::Timeout" do
    contributors = Contributors.new(@simple, not_computable_ids: Set.new)
    @simple.rpc.expects(:contributor_shortlog).raises(GitRPC::Timeout)

    response = contributors.all

    refute_predicate response, :computed?
    assert_equal [], response.value
  end

  test "contribs with legacy stealth emails are counted after disabling the email privacy setting" do
    repo = create(:repository, from_example: :simple)

    stealth_committer = create(:user)
    stealth_committer.primary_user_email.toggle_visibility

    # testing to make sure the legacy stealth email still counts when privacy is disabled
    stealth_email = "#{stealth_committer.login}@#{GitHub.stealth_email_host_name}"

    new_commit_oid = repo.commits.create(
        {
          message: "test commit",
          author: { name: "stealth", email: stealth_email },
        },
        repo.ref_to_sha("master"),
      ) do |files|
        files.add("my_new_file.txt", "check this out!\n")
      end.oid

    commit = repo.commits.find(new_commit_oid)
    assert_equal commit.author_email, stealth_email
    repo.heads.find("master").update(commit.oid, repo.owner)

    contributors = Contributors.new(repo)
    count_response = contributors.count
    assert_predicate count_response, :computed?
    assert_equal 3, count_response.value

    all_response = contributors.all
    assert_predicate all_response, :computed?
    assert_equal ["nickh", "rsanheim", stealth_committer.login],
      all_response.value.map { |user, _count| user.login }

    stealth_committer.primary_user_email.toggle_visibility

    contributors = Contributors.new(repo)
    count_response = contributors.count
    assert_predicate count_response, :computed?
    assert_equal 3, count_response.value

    all_response = contributors.all
    assert_predicate all_response, :computed?
    assert_equal ["nickh", "rsanheim", stealth_committer.login],
      all_response.value.map { |user, _count| user.login }
  end

  test "can include contributors with private profiles" do
    @nick.update!(private_profile: true)

    contributors = Contributors.new(@simple, not_computable_ids: Set.new)
    all_response = contributors.all(skip_private_profiles: false)

    assert_predicate all_response, :computed?
    assert_includes all_response.value.map { |user, _count| user.login }, @nick.login
  end

  test "can skip contributors with private profiles" do
    @nick.update!(private_profile: true)

    contributors = Contributors.new(@simple, not_computable_ids: Set.new)
    all_response = contributors.all(skip_private_profiles: true)

    assert_predicate all_response, :computed?
    refute_includes all_response.value.map { |user, _count| user.login }, @nick.login
  end

  if GitHub.enterprise?
    test "set of shortlog not computable is empty" do
      assert Contributors::SHORTLOG_NOT_WEB_COMPUTABLE_REPOSITORY_IDS.empty?
    end
  end
end

class EmuContributorsTest < GitHub::TestCase
  include ContributorsSharedTests

  fixtures do
    @rtomayko = create(:emu, :owner, login: "rtomayko", email: "rtomayko@gmail.com")
    business = @rtomayko.enterprise_managed_business

    @nick = create(:emu, business: business, login: "nickh", email: "nickh@github.com")
    @rob = create(:emu, business: business, login: "rsanheim", email: "rsanheim@gmail.com")

    @simple   = create(:repository, name: "simple", owner: @rtomayko, from_example: :simple)


    @contributors = ["nickh_#{business.shortcode}", "rsanheim_#{business.shortcode}"]
  end

  setup do
    @simple.update_default_branch("master")
    reset_cache
  end
end unless GitHub.single_business_environment?
