# typed: true
# frozen_string_literal: true

require "test_helper"
require "json"

class RetiredNamespaceTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "jisoo")
    @repo = create(:repository, owner: @owner)
    @retired_repo = create(:repository, owner: @owner, name: "retired")
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    @retired_namespace = create(:retired_namespace,
      owner: @owner,
      name: @retired_repo.name,
    )
    @claimable = create(:retired_namespace,
      owner_login: "blackpink-in-your-area",
      owner_id: @owner.id,
      name: "boombayah",
    )
  end

  test "create from repository" do
    refute RetiredNamespace.retired? @repo.nwo
    retired_namespace = RetiredNamespace.create_from_repository!(@repo)
    assert retired_namespace
    assert_equal RetiredNamespace, retired_namespace.class
    assert_equal @repo.name.downcase, retired_namespace.name
    assert_equal @owner.login.downcase, retired_namespace.owner_login
    assert_equal @owner.id, retired_namespace.owner_id
    assert RetiredNamespace.retired? @repo.nwo
  end

  test "retires redirects when a parent repository is destroyed" do
    refute RetiredNamespace.retired? "#{@owner.login}/redirect"
    RepositoryRedirect.create! repository_id: @repo.id, repository_name: "#{@owner.login}/redirect"
    RetiredNamespace.create_from_repository!(@repo)
    assert RetiredNamespace.retired? "#{@owner.login}/redirect"
  end

  test "retires redirect directly" do
    refute RetiredNamespace.retired? "#{@owner.login}/redirect2"
    RepositoryRedirect.create! repository_id: @repo.id, repository_name: "#{@owner.login}/redirect2"
    RetiredNamespace.retire_redirects!(@repo)
    assert RetiredNamespace.retired? "#{@owner.login}/redirect2"
  end

  test "sets owner_id on the namespace when retiring redirects" do
    RepositoryRedirect.create! repository_id: @repo.id, repository_name: "#{@owner.login}/redirect2"
    RetiredNamespace.retire_redirects!(@repo)

    assert RetiredNamespace.exists?(owner_id: @owner.id, name: "redirect2", owner_login: @owner.login)
  end

  test "doesn't try to double retire case-sensitive redirects" do
    refute RetiredNamespace.retired? "#{@owner.login}/redirect3"
    RepositoryRedirect.create! repository_id: @repo.id, repository_name: "#{@owner.login}/Redirect3"
    RepositoryRedirect.create! repository_id: @repo.id, repository_name: "#{@owner.login.upcase}/redirect3"
    RetiredNamespace.retire_redirects!(@repo)
    assert RetiredNamespace.retired? "#{@owner.login}/redirect3"
  end

  test "checking if a namespace is retired" do
    assert RetiredNamespace.retired?("#{@owner.login}/retired")
    assert RetiredNamespace.retired?(@owner.login, "retired")
    repo = create :repository, owner: @owner
    refute RetiredNamespace.retired?(@owner.login, repo.name)
  end

  if GitHub.retired_namespaces_on_deletion_enabled?
    test "knows a popular repository should be retired" do
      stub_pond_response({ data: { count: 1000 } })
      assert RetiredNamespace.should_retire? @repo
    end

    test "knows a repository for a marketplace-listed action should be retired" do
      stub_pond_response({ data: { count: 1 } })
      action = create(:repository_action, :listed)
      assert RetiredNamespace.should_retire? action.repository
    end

    test "knows a repository for a previously marketplace-listed action should be retired" do
      stub_pond_response({ data: { count: 1 } })
      action = create(:repository_action, :delisted)
      assert RetiredNamespace.should_retire? action.repository
    end

    test "doesn't retire user pages repos" do
      stub_pond_response({ data: { count: 1000 } })
      repo = create :repository, owner: @owner, name: "#{@owner}.github.io"
      refute RetiredNamespace.should_retire? repo
    end

    test "doesn't retire user pages repos with names that do not match owner" do
      # https://github.com/github/communities/issues/1677
      stub_pond_response({ data: { count: 1000 } })
      repo = create :repository, owner: @owner, name: "collei.github.io"
      refute RetiredNamespace.should_retire? repo
    end

    test "records stats when checking recent clones" do
      stub_pond_response({ data: { count: 1000 } })
      RetiredNamespace.should_retire? @repo
      stat = GitHub.dogstats.operations.find { |operation| operation.stat == "retired_namespace.count_recent_clones" }
      assert stat, "Expected a retired_namespace.count_recent_clones stat to have been sent"
    end

    test "knows a repository without many clones shouldn't be retired" do
      stub_pond_response({ data: { count: 1 } })
      refute RetiredNamespace.should_retire? @repo
    end

    test "knows a repository with an unlisted action and low usage shouldn't be retired" do
      stub_pond_response({ data: { count: 1 } })
      action = create(:repository_action, :unlisted)

      now = Time.now
      (0..10).each_entry do |lookback|
        Actions::RepositoryUsage.set_usage_for(action.repository.id, time: now - lookback.days, count: 10)
      end

      refute RetiredNamespace.should_retire? action.repository
    end

    test "knows a repository with an unlisted action and high usage should be retired" do
      stub_pond_response({ data: { count: 1 } })
      action = create(:repository_action, :unlisted)

      now = Time.now
      (0..10).each_entry do |lookback|
        Actions::RepositoryUsage.set_usage_for(action.repository.id, time: now - lookback.days, count: 20)
      end

      assert RetiredNamespace.should_retire? action.repository
    end
  end

  test "downcases the owner and name" do
    retired_namespace = RetiredNamespace.create owner_login: "OWNER", name: "NAME"
    assert_equal "owner", retired_namespace.owner_login
    assert_equal "name", retired_namespace.name
  end

  test "exposes the name" do
    assert_equal "retired", @retired_namespace.name
  end

  test "exposes the owner login" do
    assert_equal @owner.login, @retired_namespace.owner_login
  end

  test "exposes the owner" do
    assert_equal @owner, @retired_namespace.owner
  end

  test "exposes the nwo" do
    assert_equal "#{@owner.login}/retired", @retired_namespace.nwo
  end

  test "exposes retired namespaces on User model" do
    assert_equal [@retired_namespace], @owner.retired_namespaces
  end

  if GitHub.retired_namespaces_on_deletion_enabled?
    test "retires repository namespaces when a user is renamed" do
      stub_pond_response({ data: { count: 1000 } })
      old_login = @owner.login
      refute RetiredNamespace.retired? @repo.nwo
      @owner.rename! "#{old_login}2"
      @repo.reload
      assert RetiredNamespace.retired? "#{old_login}/#{@repo.name}"
      refute RetiredNamespace.retired? @repo.nwo
    end

    test "doesn't retire namespaces when the login's case changes" do
      stub_pond_response({ data: { count: 1000 } })
      old_login = @owner.login
      refute RetiredNamespace.retired? @repo.nwo
      @owner.rename! old_login.upcase
      @repo.reload
      refute RetiredNamespace.retired? "#{old_login}/#{@repo.name}"
    end

    test "retires repository namespace when a user is deleted" do
      stub_pond_response({ data: { count: 1000 } })
      nwo = @repo.nwo
      refute RetiredNamespace.retired? nwo
      @owner.destroy
      assert RetiredNamespace.retired? nwo
    end

    test "doesn't err if a namespace is already retired when a user is deleted" do
      RetiredNamespace.create_from_repository!(@repo)
      stub_pond_response({ data: { count: 1000 } })
      nwo = @repo.nwo
      @repo.owner.destroy
      assert RetiredNamespace.retired? nwo
    end
  end

  test "prevents renaming of repositories into retired namespaces" do
    repo = create :repository, owner: @owner
    refute repo.rename("retired")
  end

  test "records stats when created" do
    RetiredNamespace.create! owner_login: @owner.login, name: "stats"
    stat = GitHub.dogstats.operations.find { |operation| operation.stat == "retired_namespace.retire" }
    assert stat, "Expected a retired_namespace.retire stat to have been sent"
  end

  test "records stats when destroyed" do
    namespace = RetiredNamespace.create! owner_login: @owner.login, name: "stats2"
    namespace.destroy
    stat = GitHub.dogstats.operations.find { |operation| operation.stat == "retired_namespace.unretire" }
    assert stat, "Expected a retired_namespace.unretire stat to have been sent"
  end

  test "doesn't allow slashes in names" do
    namespace = RetiredNamespace.new owner_login: @owner.login, name: "foo/bar"
    refute_predicate namespace, :valid?
  end

  test "doesn't allow duplicate names (case insensitive)" do
    message = "has already been taken"

    namespace = RetiredNamespace.new(owner_login: @owner.login, name: "retired")
    namespace.valid?
    assert namespace.errors[:name].include?(message)

    namespace = RetiredNamespace.new(owner_login: @owner.login, name: "RETIRED")
    namespace.valid?
    assert namespace.errors[:name].include?(message)
  end

  context "#claimable_by?" do
    test "true if actor is the owner" do
      assert @retired_namespace.claimable_by?(@owner)
    end

    test "false if the actor is not the owner" do
      refute @retired_namespace.claimable_by?(create(:user))
    end

    test "false if no owner_id is set" do
      @retired_namespace.update!(owner_id: nil)
      refute @retired_namespace.claimable_by?(@owner)
    end

    test "false if actor is nil" do
      refute @retired_namespace.claimable_by?(nil)
    end

    test "true if actor owns the owning organization and flag is enabled" do
      GitHub.flipper[:retired_org_namespaces_claimable].enable

      org = create(:organization, admin: @owner)
      @retired_namespace.update!(owner_id: org.id)

      assert @retired_namespace.claimable_by?(@owner)
    end

    test "false if actor belongs to but does not own the owning organization" do
      org = create(:organization)
      org.add_member(@owner)
      @retired_namespace.update!(owner_id: org.id)

      refute @retired_namespace.claimable_by?(@owner)
    end

    test "false if actor doesn't belong to the owning organization" do
      org = create(:organization)
      @retired_namespace.update!(owner_id: org.id)

      refute @retired_namespace.claimable_by?(@owner)
    end
  end

  context ".for" do
    test "returns retired namespace" do
      namespace = RetiredNamespace.for(owner: @owner.login, name: @retired_repo.name)
      assert_equal @retired_namespace, namespace
    end

    test "name is not case sensitive" do
      namespace = RetiredNamespace.for(owner: @owner.login, name: @retired_repo.name.upcase)
      assert_equal @retired_namespace, namespace
    end

    test "returns nil if retired namespace does not exist" do
      assert_nil RetiredNamespace.for(owner: @owner.login, name: "raze-loves-killjoy")
    end
  end

  context ".for_owner" do
    test "returns namespaces for User" do
      results = RetiredNamespace.for_owner(@owner)
      assert_equal [@claimable, @retired_namespace], results
    end

    test "returns namespaces for login for user that exists" do
      results = RetiredNamespace.for_owner(@owner.login)
      assert_equal [@claimable, @retired_namespace], results
    end

    test "returns namespaces for login for user that does not exist" do
      login = "this-does-not-exist"
      namespace = create(:retired_namespace, owner_login: login)

      results = RetiredNamespace.for_owner(login)
      assert_equal [namespace], results
    end

    test "returns empty result if no retired namespaces exist" do
      assert_empty RetiredNamespace.for_owner("this-does-not-exist")
    end
  end

  context ".retire" do
    test "retires a namespace with a User owner" do
      result = RetiredNamespace.retire(owner: @owner, name: "lady-trieu")
      assert_predicate result, :success?
      assert_empty result.errors
      assert_equal @owner.login, result.namespace.owner_login
      assert_equal @owner.id, result.namespace.owner_id
      assert_equal "lady-trieu", result.namespace.name
    end

    test "retires a namespace with a string login owner" do
      result = RetiredNamespace.retire(
        owner: "trieu-industries",
        name: "millennium-clock",
        )
      assert_predicate result, :success?
      assert_empty result.errors
      assert_equal "trieu-industries", result.namespace.owner_login
      assert_nil result.namespace.owner_id
      assert_equal "millennium-clock", result.namespace.name
    end

    test "successful for existing retired namespace for User owner" do
      result = RetiredNamespace.retire(
        owner: @owner,
        name: @retired_namespace.name,
        )
      assert_predicate result, :success?
      assert_empty result.errors
      assert_equal @retired_namespace, result.namespace
    end

    test "successful for existing retired namespace string login owner" do
      result = RetiredNamespace.retire(
        owner: @owner.login,
        name: @retired_namespace.name,
        )
      assert_predicate result, :success?
      assert_empty result.errors
      assert_equal @retired_namespace, result.namespace
    end

    test "requires an owner" do
      result = RetiredNamespace.retire(owner: nil, name: "millennium-clock")
      refute_predicate result, :success?
      assert_equal ["Both `owner` and `name` are required"], result.errors
      assert_nil result.namespace
    end

    test "requires a name" do
      result = RetiredNamespace.retire(owner: @owner, name: nil)
      refute_predicate result, :success?
      assert_equal ["Both `owner` and `name` are required"], result.errors
      assert_nil result.namespace
    end
  end

  context ".unretire" do
    test "unretires a namespace with a User owner" do
      result = RetiredNamespace.unretire(
        owner: @owner,
        name: @retired_namespace.name,
        )
      assert_predicate result, :success?
      assert_empty result.errors
      assert_nil result.namespace
    end

    test "unretires a namespace with a string login owner" do
      result = RetiredNamespace.unretire(
        owner: @owner.login,
        name: @retired_namespace.name,
        )
      assert_predicate result, :success?
      assert_empty result.errors
      assert_nil result.namespace
    end

    test "successful if namespace is not retired for User owner" do
      result = RetiredNamespace.unretire(
        owner: @owner,
        name: "this-does-not-exist",
        )
      assert_predicate result, :success?
      assert_empty result.errors
      assert_nil result.namespace
    end

    test "successful if namespace is not retired for string login owner" do
      result = RetiredNamespace.unretire(
        owner: @owner.login,
        name: @retired_namespace.name,
        )
      assert_predicate result, :success?
      assert_empty result.errors
      assert_nil result.namespace
    end

    test "requires an owner" do
      result = RetiredNamespace.unretire(owner: nil, name: "millennium-clock")
      refute_predicate result, :success?
      assert_equal ["Both `owner` and `name` are required"], result.errors
      assert_nil result.namespace
    end

    test "requires a name" do
      result = RetiredNamespace.unretire(owner: @owner, name: nil)
      refute_predicate result, :success?
      assert_equal ["Both `owner` and `name` are required"], result.errors
      assert_nil result.namespace
    end
  end

  unless GitHub.retired_namespaces_on_deletion_enabled?
    test "allows repository namespace reuse when a user is renamed" do
      stub_pond_response({ data: { count: 1000 } })
      old_login = @owner.login
      @owner.rename! "#{old_login}2"
      @repo.reload
      refute RetiredNamespace.retired? "#{old_login}/#{@repo.name}"
    end

    test "allows repository namespace reuse when a user is deleted" do
      stub_pond_response({ data: { count: 1000 } })
      nwo = @repo.nwo
      @owner.destroy
      refute RetiredNamespace.retired? nwo
    end
  end

  context "#unretire multiple" do
    test "unretires multiple namespaces" do
      other_retired_namespace = create(:retired_namespace, owner: @owner)
      result = RetiredNamespace.unretire_multiple(user: @retired_namespace.owner, ids: [@retired_namespace.id, other_retired_namespace.id])

      assert_predicate result, :success?
      assert_empty result.errors
      refute RetiredNamespace.retired?(@retired_namespace.nwo)
      refute RetiredNamespace.retired?(other_retired_namespace.nwo)
    end

    test "returns early with an error if any namespace is not retired" do
      other_retired_namespace = create(:retired_namespace, owner: @owner)
      user = create(:user)
      result = RetiredNamespace.unretire_multiple(user: user, ids: [@retired_namespace.id, other_retired_namespace.id])

      refute_predicate result, :success?
      assert_equal ["Retired namespace with id #{@retired_namespace.id} not found"], result.errors
      assert RetiredNamespace.retired?(@retired_namespace.nwo)
      assert RetiredNamespace.retired?(other_retired_namespace.nwo)
    end
  end

  private

  def stub_pond_response(body)
    stub_request(:get, /pond.test/).
      to_return({
        status: 200,
        body: body.to_json,
        headers: { "content-type" => "json" },
      })
  end
end
