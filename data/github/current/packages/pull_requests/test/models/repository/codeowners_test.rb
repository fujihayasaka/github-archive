# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryCodeownersTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper
  include GitHub::QueryAssertionTestHelpers
  include PerformanceTestHelpers

  fixtures do
    @owner = create(:user, login: "abc")
    @org = create(:organization, admin: @owner)
    @team = create :team, organization: @org, privacy: :closed
    @collaborator = create(:user, login: "def")
    @by_email_verified = create(:verified_user, email: +"verified.collaborator@example.com")
    @by_email_unverified = create(:user, email: +"unverified.collaborator@example.com")

    @repo = create(:repository, owner: @org)
    @repo.add_member(@collaborator)
    @repo.add_member(@by_email_verified)
    @repo.add_member(@by_email_unverified)
    @team.add_repository(@repo, :push)

    @readonly_member = create(:user)
    @repo.add_member(@readonly_member, action: :read)
    @readonly_team = create(:team, organization: @org)
    @readonly_team.add_repository(@repo, :read)

    @unauthorized_user = create(:user)
    @unauthorized_team = create(:team, organization: @org)
  end

  setup do
    reset_repo_root
    example_repo :pull_request_source, @repo
  end

  context "loading CODEOWNERS file" do
    context "file does not exist at the default branch" do
      test "does not call methods to load the file for the default branch" do
        # CODEOWNERS does not exist at the default branch
        @repo.expects(:codeowners?).returns(false)

        @repo.expects(:directory).never
        PreferredFile.expects(:find).never
        @repo.expects(:tree_entry).never
        Codeowners::File.expects(:new).never

        Repository::Codeowners.new(@repo)

        assert_dogstats_distribution(1, "codeowners.init")
      end

      # Repository#codeowners? can be true only if CODEOWNERS exists at the default branch
      # for non-default branches, we shall always try to fetch the file
      test "calls the methods to load the file for the non default branch" do

        tree_entry = Struct.new(:data, :truncated?).new("CODEOWNERS file content", false)
        # CODEOWNERS does not exist at the default branch
        @repo.stubs(:codeowners?).returns(false)
        @repo.stubs(:directory).with("non-default-branch").returns(Struct.new(:path).new("some-dir-path"))

        PreferredFile.expects(:find)
          .with(directory: @repo.directory("non-default-branch"), type: :codeowners)
          .returns(tree_entry)

        codeowners_file = stub("Codeowners::File", rules: [], errors: [])
        Codeowners::File.expects(:new).with("CODEOWNERS file content", anything).returns(codeowners_file)

        Repository::Codeowners.new(@repo, ref: "non-default-branch")

        assert_dogstats_distribution(1, "codeowners.init")
      end
    end
  end

  test "knows that a repo has a codeowners file" do
    create_owners_file(@repo)
    RepositoryCheckPreferredFilesJob.perform_now(@repo.id, @repo.default_oid)

    assert @repo.codeowners?, "Should return true if codeowners file exists"
  end

  test "reads owners file" do
    create_owners_file(@repo)

    owners = Repository::Codeowners.new(@repo, paths: ["app/assets/upload.js", "app/models/user.rb"])

    if GitHub.email_verification_enabled?
      assert_same_elements [@owner, @collaborator, @by_email_verified], owners.owners
    else
      assert_same_elements [@owner, @collaborator, @by_email_verified, @by_email_unverified], owners.owners
    end

    assert_dogstats_distribution(1, "codeowners.owners_from_file.timing", tags: ["num_paths:0-3", "num_rules:0-5"])
  end

  test "reads owners file beyond the default rpc tree entry size" do
    TreeEntry.any_instance.stubs(:truncated?).returns(true)
    TreeEntry.any_instance.stubs(:size).returns(501.kilobytes)
    create_owners_file(@repo)

    expected_log = {
      "code.namespace": "Repository::Codeowners",
      "gh.repo.id": @repo.id,
      "gh.pull_request.codeowners.file_size": 501.kilobytes,
      "Body": "Codeowners file truncated",
    }

    assert_logged(**expected_log) do
      owners = Repository::Codeowners.new(@repo, paths: ["app/assets/upload.js", "app/models/user.rb"])

      if GitHub.email_verification_enabled?
        assert_same_elements [@owner, @collaborator, @by_email_verified], owners.owners
      else
        assert_same_elements [@owner, @collaborator, @by_email_verified, @by_email_unverified], owners.owners
      end
    end
  end

  test "memoizes the matching result" do
    create_owners_file(@repo, contents: <<~OWNERS)
      *.js @#{@owner} @#{@team}
      *.rb @#{@collaborator}
    OWNERS

    owners = Repository::Codeowners.new(@repo, paths: ["app/assets/upload.js"])
    result = stub("result")
    owners.file.expects(:match).once.returns(result)

    # Hack: We are calling a private method here because stubbing out a realistic
    # result object that is used by a public method would be complicated and very
    # brittle. Forgive us.
    assert_equal result, owners.send(:result_from_file)
    assert_equal result, owners.send(:result_from_file)
  end

  test "logs when owners file truncated yet empty (size > 3 MB)" do
    TreeEntry.any_instance.stubs(:truncated?).returns(true)
    TreeEntry.any_instance.stubs(:size).returns(3.megabyte)
    TreeEntry.any_instance.stubs(:data).returns("")
    create_owners_file(@repo)

    expected_log = {
      "code.namespace": "Repository::Codeowners",
      "gh.repo.id": @repo.id,
      "gh.pull_request.codeowners.file_size": 3.megabyte,
      "Body": "Codeowners file exceeds file limit",
    }

    assert_logged(**expected_log) do
      Repository::Codeowners.new(@repo, paths: ["app/assets/upload.js", "app/models/user.rb"])
    end
  end

  test "logs when the owners file is invalid" do
    contents = "foo/*** @foo"
    create_owners_file(@repo, contents: contents)

    expected_log = {
      "code.namespace": "Repository::Codeowners",
      "gh.repo.id": @repo.id,
      "gh.pull_request.codeowners.file_size": contents.bytesize,
      "Body": "Codeowners file invalid",
    }

    assert_logged(**expected_log) do
      Repository::Codeowners.new(@repo, paths: ["app/assets/upload.js", "app/models/user.rb"])
    end
  end

  test "logs when the file contains some valid rules and some errors" do
    contents = "*.rb @acmeinc/ruby\nfoo/*** @foo\n"
    create_owners_file(@repo, contents: contents)

    expected_log = {
      "code.namespace": "Repository::Codeowners",
      "gh.repo.id": @repo.id,
      "gh.pull_request.codeowners.file_size": contents.bytesize,
      "Body": "Codeowners file contained some errors",
    }

    assert_logged(**expected_log) do
      Repository::Codeowners.new(@repo, paths: ["app/assets/upload.js", "app/models/user.rb"])
    end
  end

  test "supports team codeowners" do
    create_owners_file(@repo, contents: <<~OWNERS)
      *.js @#{@owner} @#{@team}
      *.rb @#{@collaborator}
    OWNERS

    owners = Repository::Codeowners.new(@repo, paths: ["app/assets/upload.js"])
    assert_same_elements [@owner, @team], owners.owners
    assert_same_elements [@team], owners.teams
  end

  test "filters out teams that are not visible to a viewer" do
    create_owners_file(@repo, contents: <<~OWNERS)
      * @#{@owner} @#{@team}
    OWNERS

    Team.any_instance.expects(:async_visible_to?).with(@owner).returns(Promise.resolve(false))

    owners = Repository::Codeowners.new(@repo, paths: ["app/assets/upload.js"])
    assert_same_elements [@owner, @team], owners.owners
    assert_same_elements [@owner], owners.owners_visible_to(@owner)
  end

  test "knows the path of the CODEOWNERS file" do
    create_owners_file(@repo, path: "CODEOWNERS")
    owners = Repository::Codeowners.new(@repo)
    assert_equal "CODEOWNERS", owners.path

    example_repo :pull_request_source, @repo
    create_owners_file(@repo, path: ".github/CODEOWNERS")
    owners = Repository::Codeowners.new(@repo)
    assert_equal ".github/CODEOWNERS", owners.path
  end

  test "knows the tree OID the codeowners file was read from" do
    create_owners_file(@repo)

    owners = Repository::Codeowners.new(@repo)
    assert_equal @repo.default_oid, owners.tree_oid
  end

  test "can return owners mapped to the rules declaring them owners" do
    create_owners_file(@repo, contents: <<~OWNERS)
      *  @#{@owner}
      *.js @#{@owner} @#{@team}
      *.rb @#{@collaborator}
    OWNERS

    owners = Repository::Codeowners.new(@repo, paths: ["README.md", "app/assets/upload.js"])
    by_owner = owners.rules_by_owner

    assert_same_elements [@owner, @team], by_owner.keys
    owner_rules = by_owner[@owner]
    assert_equal 2, owner_rules.count
    assert_same_elements [1, 2], owner_rules.map(&:line)
    assert_same_elements ["*", "*.js"], owner_rules.map { |r| r.pattern.to_s }

    team_rules = by_owner[@team]
    assert_equal 1, team_rules.count
    assert_equal [2], team_rules.map(&:line)
    assert_equal ["*.js"], team_rules.map { |r| r.pattern.to_s }
  end

  test "can return the paths owned by a given owner" do
    create_owners_file(@repo, contents: <<~OWNERS)
      *.md @#{@owner}
      *.js @#{@owner} @#{@team}
      *.rb @#{@collaborator}
    OWNERS

    owners = Repository::Codeowners.new(@repo, paths: ["README.md", "app/assets/upload.js", "other.rb"])

    assert_same_elements ["other.rb"], owners.paths_for_owner(@collaborator)
    assert_same_elements ["app/assets/upload.js"], owners.paths_for_owner(@team)
    assert_same_elements ["README.md", "app/assets/upload.js"], owners.paths_for_owner(@owner)
  end

  test "can return the paths owned by a given owner that includes paths owned by their teams" do
    @team.add_member(@owner)

    create_owners_file(@repo, contents: <<~OWNERS)
      *.js @#{@team}
      *.rb @#{@team}
    OWNERS

    owners = Repository::Codeowners.new(@repo, paths: ["README.md", "app/assets/upload.js", "other.rb"])

    assert_same_elements ["app/assets/upload.js", "other.rb"], owners.paths_for_owner(@owner)
  end

  test "memoizes results when calling paths_for_owner" do
    create_owners_file(@repo, contents: <<~OWNERS)
      *  @#{@team}
      *.rb @#{@collaborator}
    OWNERS

    owners = Repository::Codeowners.new(@repo, paths: ["README.md", "other.rb"])

    @owner.expects(:team_ids).once.returns([@team.id])

    rpc_counts = {
      authzd: {
        single: 0,
        batch: 0,
      },
      gitrpc: 0,
    }

    # Check for expected queries
    assert_rpc_calls(rpc_counts) do
      # Repository::Codeowners::ActiveRecordOwnerResolver#users_by_username
      # User::AuthorEmailsDependency::ClassMethods#find_by_emails
      # Repository::Codeowners::ActiveRecordOwnerResolver#teams_by_teamname (2)
      # Ability::Subject#subject_actor_ids (2)
      # Repository::AbilityDependency#fgp_users
      # Repository::AbilityDependency#all_repo_role_grants (2)
      # Platform::Loaders::UserTeams#fetch
      # User::OrganizationsDependency#team_ids
      assert_query_count(TestEnv.test_all_features? ? 9 : 10) do
        owners.paths_for_owner(@owner)
      end
    end

    assert_rpc_calls(rpc_counts) do
      assert_query_counts(0) do
        owners.paths_for_owner(@owner)
      end
    end

    # Check for accuracy
    assert_equal %w(README.md), owners.paths_for_owner(@owner)
    assert_equal %w(README.md), owners.paths_for_owner(@owner)
    assert_equal %w(other.rb), owners.paths_for_owner(@collaborator)
  end

  test "can return rules mapped to owners" do
    create_owners_file(@repo, contents: <<~OWNERS)
      *  @#{@owner}
      *.js @#{@owner} @#{@team}
      *.rb @#{@collaborator}
    OWNERS

    owners = Repository::Codeowners.new(@repo, paths: ["README.md", "app/assets/upload.js"])
    by_rule = owners.owners_by_rule

    assert_equal 2, by_rule.keys.count
    assert_equal [2, 1], by_rule.keys.map(&:line)

    line_2_rule = by_rule.keys.find { |r| r.line == 2 }
    owners = by_rule[line_2_rule]
    assert_same_elements [@owner, @team], owners
  end

  test "doesn't return owners without write access to the repo" do
    create_owners_file(@repo, contents: <<~OWNERS)
      *  @#{@owner}  @#{@readonly_member}  @#{@readonly_team}  @#{@unauthorized_user}  @#{@unauthorized_team}
    OWNERS

    owners = Repository::Codeowners.new(@repo, paths: ["README.md", "app/assets/upload.js"])
    assert_equal [@owner], owners.to_a
  end

  test "doesn't return secret teams" do
    secret_team = create :team, organization: @org, privacy: :secret
    secret_team.add_repository(@repo, :push)

    create_owners_file(@repo, contents: <<~OWNERS)
      *  @#{@owner}  @#{@team}  @#{secret_team}
    OWNERS

    owners = Repository::Codeowners.new(@repo, paths: ["README.md", "app/assets/upload.js"])
    assert_equal [@owner, @team], owners.to_a
  end

  test "returns nested teams with inherited write access" do
    subteam = create :team, organization: @org, parent_team_id: @team.id, privacy: :closed
    sub_subteam = create :team, organization: @org, parent_team_id: subteam.id, privacy: :closed

    create_owners_file(@repo, contents: <<~OWNERS)
      *  @#{@team} @#{subteam} @#{sub_subteam}
    OWNERS

    owners = Repository::Codeowners.new(@repo, paths: ["README.md", "app/assets/upload.js"])
    assert_same_elements [@team, subteam, sub_subteam], owners.to_a

    create_owners_file(@repo, contents: <<~OWNERS)
      *  @#{subteam} @#{sub_subteam}
    OWNERS

    owners = Repository::Codeowners.new(@repo, paths: ["README.md", "app/assets/upload.js"])
    assert_same_elements [subteam, sub_subteam], owners.to_a

    create_owners_file(@repo, contents: <<~OWNERS)
      *  @#{sub_subteam}
    OWNERS

    owners = Repository::Codeowners.new(@repo, paths: ["README.md", "app/assets/upload.js"])
    assert_same_elements [sub_subteam], owners.to_a
  end

  test "can return owners for a path" do
    create_owners_file(@repo, contents: <<~OWNERS)
      *  @#{@owner}
      *.js @#{@owner} @#{@team}
      *.rb @#{@collaborator}
    OWNERS

    owners = Repository::Codeowners.new(@repo, paths: ["README.md", "app/assets/upload.js"])

    assert_same_elements [@owner, @team], owners.owners_for_path("app/assets/upload.js")
  end

  test "a path with no owner overrides default owners" do
    create_owners_file(@repo, contents: <<~OWNERS)
      *  @#{@team}
      docs/
    OWNERS

    owners = Repository::Codeowners.new(@repo, paths: ["README.md", "docs/hello_world.md"])

    assert_empty owners.owners_for_path("docs/hello_world.md")
  end

  test "can return rule for a path" do
    create_owners_file(@repo, contents: <<~OWNERS)
      *  @#{@owner}
      *.js @#{@owner} @#{@team}
      *.rb @#{@collaborator}
    OWNERS

    owners = Repository::Codeowners.new(@repo, paths: ["README.md", "app/assets/upload.js"])

    assert rule = owners.rule_for_path("app/assets/upload.js")
    assert_equal 2, rule.line
  end

  test "isn't case sensitive" do
    create_owners_file(@repo, contents: <<~OWNERS)
      *  @#{@owner.to_s.upcase} @#{@team.to_s.upcase}
    OWNERS

    owners = Repository::Codeowners.new(@repo, paths: ["README.md"])

    assert_same_elements [@owner, @team], owners.to_a
  end

  test "returns empty owners if the CODEOWNERS file is invalid to the point causing errors" do
    create_owners_file(@repo, contents: <<~OWNERS)
      [kernel-install]
      kernel-install/ -#{@owner.to_s.upcase} -#{@team.to_s.upcase}

      [test suite]
      test/ @#{@owner.to_s.upcase}
    OWNERS

    codeowners = Repository::Codeowners.new(@repo, paths: ["kernel-install/README"])

    owners = assert_nothing_raised do
      codeowners.owners
    end

    assert_empty owners
  end

  test "doesn't return any owners if repo's plan doesn't support codeowners" do
    user = create(:user, plan: "free")
    repo = create(:private_repository, owner: user, from_example: :pull_request_source)

    refute repo.plan_supports?(:codeowners)

    create_owners_file(repo, contents: <<~OWNERS)
      *  @#{user}
    OWNERS
    owners = Repository::Codeowners.new(repo, paths: ["README.md"])

    assert_predicate owners, :none?
  end

  test "unknown owners not included in results" do
    create_owners_file(@repo, contents: <<~OWNERS)
      *  @#{@team}
      *.rb @#{@collaborator} @not-a-user
    OWNERS

    owners = Repository::Codeowners.new(@repo, paths: ["README.md", "app/models/user.rb"])

    assert_equal 2, owners.to_a.size
    assert_same_elements [@collaborator], owners.owners_for_path("app/models/user.rb")
  end

  test "does not preform extra lookups" do
    create_owners_file(@repo, contents: <<~OWNERS)
      *  @#{@owner}
      *.rb @#{@collaborator}
    OWNERS

    owners = Repository::Codeowners.new(@repo, paths: ["README.md", "app/models/user.rb"])

    assert_queries_matching /SELECT `users`\.\* FROM `users` WHERE `users`.`login`/, 1 do
      owners.owners_for_path("app/models/user.rb")
      owners.owners_for_path("README.md")
      owners.owners_for_path("app/models/user.rb")
      owners.owners_for_path("README.md")
    end
  end

  context "#owned_by?" do
    test "is false if a wildcard rule is overridden by a later rule" do
      create_owners_file(@repo, contents: <<~OWNERS)
        *  @#{@owner}
        *.rb @#{@collaborator}
      OWNERS

      owners = Repository::Codeowners.new(@repo, paths: ["README.md", "app/models/user.rb"])

      refute owners.owned_by?(owner: @owner, path: "app/models/user.rb")
      assert owners.owned_by?(owner: @collaborator, path: "app/models/user.rb")
    end

    test "is false if a team wildcard rule is overridden by a later rule" do
      assert @team.add_member(@owner)

      create_owners_file(@repo, contents: <<~OWNERS)
        *  @#{@team}
        *.rb @#{@collaborator}
      OWNERS

      owners = Repository::Codeowners.new(@repo, paths: ["README.md", "app/models/user.rb"])

      refute owners.owned_by?(owner: @owner, path: "app/models/user.rb")
      assert owners.owned_by?(owner: @collaborator, path: "app/models/user.rb")
    end
  end

  context "#exists?" do
    test "is true when there is a CODEOWNERS file" do
      create_owners_file(@repo)

      owners = Repository::Codeowners.new(@repo)

      assert_predicate owners, :exists?
    end

    test "is false when there is no a CODEOWNERS file" do
      owners = Repository::Codeowners.new(@repo)

      refute_predicate owners, :exists?
    end
  end

  private

  def create_owners_file(repository, contents: nil, path: "CODEOWNERS")
    contents ||= <<~OWNERS
        *.js @#{@owner} verified.collaborator@example.com unverified.collaborator@example.com
        *.rb @#{@collaborator}
    OWNERS

    base_ref = repository.heads.find("master")
    base_ref.append_commit({ message: "codeowners", committer: repository.owner }, repository.owner) do |files|
      files.add(path, contents)
    end
  end
end
