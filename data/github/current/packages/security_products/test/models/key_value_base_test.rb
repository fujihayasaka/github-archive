# typed: true
# frozen_string_literal: true

require "test_helper"

class KeyValueBaseTest < GitHub::TestCase
  class MockUserModel < KeyValueBase
    self.prefix_key = "kv_models/user"

    attribute :name
    attribute :enterprise, type: :boolean, default: false

    primary_index :org, :login
  end

  class MockUserModelWithExpiry < KeyValueBase
    self.prefix_key = "kv_models/user"

    attribute :name
    attribute :enterprise, type: :boolean, default: false

    primary_index :org, :login

    self.expires_in 10.days
  end

  class MockRepoModel < KeyValueBase
    self.prefix_key = "kv_models/repo"
    attribute :file_names, type: :array

    primary_index :nwo
  end

  test "it will validate models without the primary index" do
    m = MockUserModel.new
    refute m.valid?
    assert_raises(ActiveModel::ValidationError) { m.save! }
  end

  test "create!" do
    assert_nil GitHub.kv.get("kv_models/user/1/bar").value! # rubocop:todo GitHub/DoNotUseGlobalKv
    m = MockUserModel.create!(org: 1, name: "foo", login: "bar")
    assert m.persisted?
    refute m.enterprise
    refute_nil GitHub.kv.get("kv_models/user/1/bar").value! # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  test "save!" do
    assert_nil GitHub.kv.get("kv_models/user/1/bar").value! # rubocop:todo GitHub/DoNotUseGlobalKv
    m = MockUserModel.new(org: 1, name: "foo", login: "bar").save!
    assert m.persisted?
    refute m.enterprise

    assert_nil GitHub.kv.ttl("kv_models/user/1/bar").value! # rubocop:todo GitHub/DoNotUseGlobalKv
    refute_nil GitHub.kv.get("kv_models/user/1/bar").value! # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  test "save! with expiration" do
    Timecop.freeze("2023-04-18 00:00:00") do
      assert_nil GitHub.kv.get("kv_models/user/1/bar").value! # rubocop:todo GitHub/DoNotUseGlobalKv
      m = MockUserModelWithExpiry.new(org: 1, name: "foo", login: "bar").save!
      assert m.persisted?
      refute m.enterprise

      refute_nil GitHub.kv.get("kv_models/user/1/bar").value! # rubocop:todo GitHub/DoNotUseGlobalKv

      kv_ttl = GitHub.kv.ttl("kv_models/user/1/bar").value! # rubocop:todo GitHub/DoNotUseGlobalKv
      # TODO there is an edge case in this assertion that will fail when the date is 04/28 which is
      # 10 days after frozen date. When its also the system date, the KV key is automatically going
      # to be expired so the `kv_ttl` is going to be `nil`
      assert_equal kv_ttl.utc.to_date, 10.days.from_now.to_date if kv_ttl
    end
  end

  test "delete!" do
    m = MockUserModel.create!(org: 1, name: "foo", login: "bar")
    assert_nil m.delete!
    assert_nil GitHub.kv.get("kv_models/user/1/bar").value! # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  test "find" do
    MockUserModel.new(org: 1, name: "foo", login: "bar").save!
    assert_equal "foo", MockUserModel.find(org: 1, login: "bar").name
  end

  test "find errors if index is not included" do
    assert_raises(ArgumentError) { MockUserModel.find(org: 1) }
  end

  test "save! when updating an entry" do
    MockUserModel.new(org: 1, name: "Arthur N", login: "arthurnn").save!
    # rubocop:todo GitHub/DoNotUseGlobalKv
    assert_equal "Arthur N", JSON.load(GitHub.kv.get("kv_models/user/1/arthurnn").value!)["name"]
    # rubocop:enable GitHub/DoNotUseGlobalKv

    m = MockUserModel.new(org: 1, name: "Arthur Neves", login: "arthurnn").save!
    assert_equal "Arthur Neves", m.name
    # rubocop:todo GitHub/DoNotUseGlobalKv
    assert_equal "Arthur Neves", JSON.load(GitHub.kv.get("kv_models/user/1/arthurnn").value!)["name"]
    # rubocop:enable GitHub/DoNotUseGlobalKv
  end

  test "Array as attribute save and find" do
    MockRepoModel.new(nwo: "arthurnn/foo", file_names: %w[.gitignore Dockerfile]).save!

    refute_nil GitHub.kv.get("kv_models/repo/arthurnn/foo").value! # rubocop:todo GitHub/DoNotUseGlobalKv

    MockRepoModel.find(nwo: "arthurnn/foo").tap do |m|
      assert_equal %w[.gitignore Dockerfile], m.file_names
    end
  end

  test "find_all index" do
    MockUserModel.new(org: 1, login: "arthurnn").save!
    MockUserModel.new(org: 1, login: "natashaU").save!
    MockUserModel.new(org: 1, login: "anaarmas").save!

    assert_equal %w[anaarmas arthurnn natashaU], MockUserModel.find_all(org: 1).map(&:login).sort

    assert_empty MockUserModel.find_all(org: 42).map(&:login)
  end

  test "find_all index should not load records that have the same leading part of the index, if not actully match the index completely" do
    MockUserModel.new(org: 1, login: "arthurnn").save!
    MockUserModel.new(org: 11, login: "natashaU").save!

    assert_equal %w[arthurnn], MockUserModel.find_all(org: 1).map(&:login).sort
  end

  test "find_all passing a non-index key" do
    assert_raises ArgumentError do
      MockUserModel.find_all(name: "Arthur N").map(&:login)
    end

    # Giving a non-left piece of the primary index
    assert_raises ArgumentError do
      MockUserModel.find_all(login: "arthurnn").map(&:login)
    end
  end

  test "find_all + count" do
    MockUserModel.new(org: 1, login: "arthurnn").save!
    MockUserModel.new(org: 1, login: "natashaU").save!
    MockUserModel.new(org: 1, login: "anaarmas").save!

    assert_equal 3, MockUserModel.find_all(org: 1).count
    assert_equal 0, MockUserModel.find_all(org: 2).count
    assert_equal 1, MockUserModel.find_all(org: 1, login: "arthurnn").count
  end

  test "find_or_build_by" do
    MockUserModel.new(org: 1, login: "arthurnn").save!
    list = MockUserModel.find_all(org: 1)
    list.find_or_build_by(login: "arthurnn") do |m|
      assert m.persisted?
      assert_equal "arthurnn", m.login
    end

    ana = list.find_or_build_by(login: "anaarmas")
    refute ana.persisted?
    ana.save!
    assert ana.persisted?

    assert_equal 2, MockUserModel.find_all(org: 1).count

  end

  test "load_json should only load the attributes that are defined" do

    user = MockUserModel.new.load_json(JSON.dump(org: 1, login: "nickfyson", foo: "bar"))

    # loads known attributes
    assert_equal 1, user.org
    assert_equal "nickfyson", user.login

    # ignores unknown ones
    assert_raises NoMethodError do
      user.foo
    end
  end
end
