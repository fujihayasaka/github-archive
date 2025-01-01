# typed: true
# frozen_string_literal: true

require "test_helper"

class FlipperFeatureTest < GitHub::TestCase
  include AuditLogHelpers
  include GitHub::UserTestHelpers
  include StringFromBinaryTestHelper

  fixtures do
    @staff   = create :staff_admin_user, login: "staffer"
    @user    = create :user, login: "guest"

    Flipper.register(:admins) {}
    Flipper.register(:dogs) {}
    ENV["CHATTERBOX_TOKEN"] = "valid-token"
  end

  context "::updated_between" do
    test "returns all features whose rollout_updated_at is in the window" do
      feature_a = create(:flipper_feature, rollout_updated_at: Time.new(1000, 01, 01))
      feature_b = create(:flipper_feature, rollout_updated_at: Time.new(3000, 01, 01))
      assert_includes FlipperFeature.updated_between("2000-01-01", "5000-01-01"), feature_b
      refute_includes FlipperFeature.updated_between("2000-01-01", "5000-01-01"), feature_a
    end

    test "defaults to the year two thousand when no starts passed in" do
      nineteen_ninety_nine = create(:flipper_feature, rollout_updated_at: Time.new(1999))
      refute_includes FlipperFeature.updated_between(nil, "5000-01-01"), nineteen_ninety_nine
    end

    test "defaults to current time when no ends passed in" do
      one_hudred_days_from_now = create(:flipper_feature, rollout_updated_at: Time.new + 100.days)
      refute_includes FlipperFeature.updated_between("1000-01-01", nil), one_hudred_days_from_now
    end
  end

  context "::service_name_like" do
    test "returns all features whose service name matches (naively)" do
      feature_a = create(:flipper_feature, service_name: "feature_a_service")
      feature_b = create(:flipper_feature, service_name: "feature_b_service")
      assert_includes FlipperFeature.service_name_like(feature_b.service_name), feature_b
      refute_includes FlipperFeature.service_name_like(feature_b.service_name), feature_a
    end

    test "handles when multiple, comma separated names are passed in" do
      feature_a = create(:flipper_feature, service_name: "feature_a_service")
      feature_b = create(:flipper_feature, service_name: "feature_b_service")
      query = [feature_a, feature_b].map(&:service_name).join(", ")
      assert_includes FlipperFeature.service_name_like(query), feature_b
      assert_includes FlipperFeature.service_name_like(query), feature_a
    end

    test "returns all features if no name passed in" do
      feature_a = create(:flipper_feature, service_name: "feature_a_service")
      feature_b = create(:flipper_feature, service_name: "feature_b_service")
      assert_includes FlipperFeature.service_name_like(nil), feature_b
      assert_includes FlipperFeature.service_name_like(nil), feature_a
    end
  end

  context "::fully_enabled" do
    test "returns features that are fully enabled" do
      feature_boolean_on = create(:flipper_feature)
      feature_boolean_off = create(:flipper_feature)
      feature_actor_on = create(:flipper_feature)
      feature_actor_off = create(:flipper_feature)

      feature_boolean_on.enable
      feature_actor_on.enable_percentage_of_actors(100)
      feature_actor_off.enable_percentage_of_actors(0)

      result = FlipperFeature.fully_enabled
      assert_includes result, feature_boolean_on
      refute_includes result, feature_boolean_off
      assert_includes result, feature_actor_on
      refute_includes result, feature_actor_off
    end
  end

  context "::fully_disabled" do
    test "returns features that are fully disabled" do
      feature_boolean_on = create(:flipper_feature)
      feature_boolean_off = create(:flipper_feature)
      feature_actor_on = create(:flipper_feature)
      feature_actor_off = create(:flipper_feature)

      feature_boolean_on.enable
      feature_actor_on.enable_percentage_of_actors(100)
      feature_actor_off.enable_percentage_of_actors(0)

      result = FlipperFeature.fully_disabled
      assert_includes result, feature_boolean_off
      refute_includes result, feature_boolean_on
      assert_includes result, feature_actor_off
      refute_includes result, feature_actor_on
    end
  end

  context "::staff_shipped" do
    test "returns only features that are staff shipped" do
      staff_shipped_feature = create(:flipper_feature)
      staff_shipped_feature.enable_group(:preview_features)
      other_feature = create(:flipper_feature)
      staff_then_fully_shipped_feature = create(:flipper_feature)
      staff_then_fully_shipped_feature.enable_group(:preview_features)
      staff_then_fully_shipped_feature.enable

      result = FlipperFeature.staff_shipped
      assert_includes result, staff_shipped_feature
      refute_includes result, other_feature
      refute_includes result, staff_then_fully_shipped_feature
    end
  end

  context "::actor_or_percentage" do
    test "returns only features that have non-min/max actor/percentage gates" do
      feature_boolean_on = create(:flipper_feature)
      feature_boolean_off = create(:flipper_feature)
      feature_actors_on = create(:flipper_feature)
      feature_actors_off = create(:flipper_feature)
      feature_actors_partial = create(:flipper_feature)
      feature_time_on = create(:flipper_feature)
      feature_time_partial = create(:flipper_feature)

      feature_boolean_on.enable
      feature_actors_on.enable_percentage_of_actors(100)
      feature_actors_off.enable_percentage_of_actors(0)
      feature_actors_partial.enable_percentage_of_actors(50)
      feature_time_on.enable_percentage_of_time(100)
      feature_time_partial.enable_percentage_of_time(50)

      result = FlipperFeature.actor_or_percentage
      assert_includes result, feature_actors_partial
      assert_includes result, feature_time_partial
      refute_includes result, feature_actors_on
      refute_includes result, feature_time_on
      refute_includes result, feature_actors_off
      refute_includes result, feature_boolean_on
      refute_includes result, feature_boolean_off
    end
  end

  context "github_enabled?" do
    test "false when fully_enabled?" do
      feature = create(:flipper_feature, name: "my_feature")
      feature.enable
      refute_predicate feature, :github_enabled?
    end

    test "true when preview_features group is enabled" do
      feature = build(:flipper_feature, name: "test_feature")
      feature.enable_group(:preview_features)
      assert_predicate feature, :github_enabled?
    end

    test "false when actors is empty" do
      feature = build(:flipper_feature, name: "test_feature")
      refute_predicate feature, :github_enabled?
    end

    test "false when a user actor is not an employee" do
      feature = create(:flipper_feature, name: "test_feature")
      feature.enable(create(:user))
      refute_predicate feature, :github_enabled?
    end

    test "false when a repo actor is not from GitHub or Microsoft" do
      feature = create(:flipper_feature, name: "test_feature")
      feature.enable(create(:repository))
      refute_predicate feature, :github_enabled?
    end

    test "false when a org actor is not GitHub" do
      feature = create(:flipper_feature, name: "test_feature")
      feature.enable(create(:organization))
      refute_predicate feature, :github_enabled?
    end

    test "false when a team actor is not owned by GitHub" do
      feature = create(:flipper_feature, name: "test_feature")
      feature.enable(create(:team))
      refute_predicate feature, :github_enabled?
    end

    test "true when actors all github or owned by github unless enterprise" do
      user = create(:user, :staff)
      microsoft_org = create(:organization, name: "microsoft")
      integrations_org = create(:organization, name: "integrations")

      FlipperFeature.stub_const(:GITHUB_ORG_ID, github_org.id) do
        feature = create(:flipper_feature, name: "test_feature")
        feature.enable(github_org) # Enabled on GitHub
        feature.enable(create(:private_repository, owner: github_org)) # Enabled on github org repo
        feature.enable(create(:private_repository, owner: microsoft_org)) # Enabled on microsoft org repo
        feature.enable(create(:private_repository, owner: integrations_org)) # Enabled on integrations org repo
        feature.enable(create(:team, organization: github_org)) # Enabled on github org team
        feature.enable(user) # Enabled on github employee

        if GitHub.enterprise?
          refute_predicate feature, :github_enabled?
        else
          assert_predicate feature, :github_enabled?
        end
      end
    end
  end

  context "tracking_issue_url validation" do
    test "presence is required" do
      refute_predicate build(:flipper_feature, tracking_issue_url: nil), :valid?
    end

    test "tracking issue must be a github or proxima url" do
      refute_predicate build(:flipper_feature, tracking_issue_url: "google.com"), :valid?
      refute_predicate build(:flipper_feature, tracking_issue_url: "https://google.com"), :valid?
      assert_predicate build(:flipper_feature, tracking_issue_url: "https://github.com/github/github/issue/42"), :valid?
      assert_predicate build(:flipper_feature, tracking_issue_url: "https://github.com/github/"), :valid?
      assert_predicate build(:flipper_feature, tracking_issue_url: "https://github.ghe.com/"), :valid?
    end
  end

  context "service validation" do
    test "invalid without a service" do
      GitHub::ServiceCatalog.stubs(:enabled?).returns(true)
      feature = build(:flipper_feature, name: name, service_name: nil)

      refute_predicate feature, :valid?
      assert_equal(["can't be blank"], feature.errors[:service_name])
    end

    test "valid with a service" do
      GitHub::ServiceCatalog.stubs(:enabled?).returns(true)
      feature = build(:flipper_feature, name: name, service_name: "my service")

      assert feature.valid?
    end

    test "valid if ServiceCatalog is not enabled" do
      GitHub::ServiceCatalog.stubs(:enabled?).returns(false)
      feature = build(:flipper_feature, name: name, service_name: "my service")

      assert feature.valid?
    end

    test "invalid if service name is blank, assuming the catalog is enabled" do
      GitHub::ServiceCatalog.stubs(:enabled?).returns(true)
      feature = build(:flipper_feature, name: name, service_name: "")

      refute feature.valid?
    end

    test "invalid if service name is 'github'" do
      feature = build(:flipper_feature, name: name, service_name: "github")

      refute feature.valid?
    end
  end

  context "private_github_repos" do
    test "returns only github repos" do
      org = create(:organization)
      FlipperFeature.stub_const(:GITHUB_ORG_ID, org.id) do
        microsoft_org = create(:organization, name: "microsoft")

        github_repo = create(:private_repository, owner: org)
        create(:public_repository, owner: org)
        microsoft_repo = create(:private_repository, owner: microsoft_org)

        deleted_github_repo = create(:private_repository, owner: org)
        deleted_github_repo.remove(User.ghost, synchronous: true)

        feature = create(:flipper_feature, name: "test_feature")
        feature.enable(github_repo)
        feature.enable(deleted_github_repo)
        feature.enable(microsoft_repo)
        feature.enable(create(:repository))
        feature.enable(org.owner)

        refute_same_elements [github_repo], feature.public_github_repos # Causes memoization and makes sure we dont collide
        assert_same_elements [github_repo], feature.private_github_repos
      end
    end
  end

  context "github_employees" do
    test "returns only github employees" do
      org = create(:organization)
      FlipperFeature.stub_const(:GITHUB_ORG_ID, org.id) do
        github_repo = create(:private_repository, owner: org)
        employee = create(:user, :staff)

        feature = create(:flipper_feature, name: "test_feature")
        feature.enable(github_repo)
        feature.enable(employee)
        feature.enable(create(:user))

        if GitHub.enterprise?
          assert_same_elements [], feature.github_employees
        else
          assert_same_elements [employee], feature.github_employees
        end
      end
    end
  end

  context "github_teams" do
    test "returns only github teams" do
      org = create(:organization)
      FlipperFeature.stub_const(:GITHUB_ORG_ID, org.id) do
        github_repo = create(:private_repository, owner: org)
        employee = create(:user, :staff)
        github_team = create(:team, organization: org)

        feature = create(:flipper_feature, name: "test_feature")
        feature.enable(github_repo)
        feature.enable(employee)
        feature.enable(github_team)
        feature.enable(create(:team))

        assert_same_elements [github_team], feature.github_teams
      end
    end
  end

  context "public_github_repos" do
    test "returns only github repos" do
      org = create(:organization)
      FlipperFeature.stub_const(:GITHUB_ORG_ID, org.id) do
        microsoft_org = create(:organization, name: "microsoft")

        deleted_github_repo = create(:public_repository, owner: org)
        deleted_github_repo.remove(User.ghost, synchronous: true)
        github_repo = create(:private_repository, owner: org)
        public_github_repo = create(:public_repository, owner: org)
        microsoft_repo = create(:private_repository, owner: microsoft_org)

        feature = create(:flipper_feature, name: "test_feature")
        feature.enable(github_repo)
        feature.enable(public_github_repo)
        feature.enable(deleted_github_repo)
        feature.enable(microsoft_repo)
        feature.enable(create(:repository))
        feature.enable(org.owner)

        refute_same_elements [public_github_repo], feature.private_github_repos # Causes memoization and makes sure we dont collide
        assert_same_elements [public_github_repo], feature.public_github_repos
      end
    end
  end

  context "non_github_repos" do
    test "returns all non github repos" do
      org = create(:organization)
      FlipperFeature.stub_const(:GITHUB_ORG_ID, org.id) do
        microsoft_org = create(:organization, name: "microsoft")

        deleted_repo = create(:private_repository)
        deleted_repo.remove(User.ghost, synchronous: true)
        github_repo = create(:private_repository, owner: org)
        microsoft_repo = create(:private_repository, owner: microsoft_org)
        other_repo = create(:repository)

        feature = create(:flipper_feature, name: "test_feature")
        feature.enable(github_repo)
        feature.enable(microsoft_repo)
        feature.enable(deleted_repo)
        feature.enable(other_repo)
        feature.enable(org.owner)

        assert_same_elements [microsoft_repo, other_repo], feature.non_github_repos
      end
    end
  end

  test "requires a name" do
    feature = build(:flipper_feature, name: nil)
    refute feature.valid?
    assert_equal "can't be blank", feature.errors[:name].first
  end

  test "requires a valid name" do
    ["audit log", "auditlog!", "auditlog?"].each do |name|
      feature = build(:flipper_feature, name: name)
      refute feature.valid?, "#{name} should be an invalid name"
      assert_equal ["is invalid"], feature.errors[:name]
    end
  end

  test "can contain a digit" do
    feature = build(:flipper_feature, name: "4auditlog")
    assert feature.valid?
  end

  test "can't contain emoji" do
    feature = build(:flipper_feature, name: "🐹")
    refute feature.valid?
    assert feature.errors[:name].any?
  end

  test "can't create duplicate features" do
    create(:flipper_feature, name: "audit_log")

    assert_no_difference "FlipperFeature.count" do
      feature = build(:flipper_feature, name: "audit_log")
      feature.valid?
      assert_equal ["has already been taken"], feature.errors[:name]
    end
  end

  test "uniqueness validation is case insensitive" do
    create(:flipper_feature, name: "case_sensitivity")

    assert_no_difference "FlipperFeature.count" do
      feature = build(:flipper_feature, name: "case_senSITIVITY")
      feature.valid?
      assert_equal ["has already been taken"], feature.errors[:name]
    end
  end

  test "internal API is protected" do
    assert_raises NoMethodError do
      T.unsafe(FlipperFeature).find_or_create_by!(name: "foo")
    end
  end

  test "returns name for to_param" do
    feature = build(:flipper_feature, name: "fancy-feast")
    assert_equal "fancy-feast", feature.to_param
  end

  test "can be enabled" do
    feature = create(:flipper_feature, name: "audit_log")
    feature.enable

    assert_predicate feature, :enabled?
    assert_predicate feature, :on?
  end

  test "can lookup feature" do
    feature = create(:flipper_feature, name: "audit_log")
    feature.enable(@user)

    assert_equal feature, FlipperFeature.find_by(name: :audit_log)
  end

  test "cleans up related records when destroyed" do
    # issue_events_delete_separate_queue is unrelated to this test but used in DestroyDependentRecordsJob,
    # setting its value so the count diff is correct
    GitHub.flipper[:issue_events_delete_separate_queue].enable
    feature = create(:flipper_feature, name: "audit_log")
    feature.enable(@user)

    perform_enqueued_jobs only: [DestroyDependentRecordsJob] do
      assert_difference "FlipperGate.count", -1 do
        feature.destroy
      end
    end

    assert_nil FlipperFeature.find_by(name: "audit_log")
  end

  test "cleans up cache when destroyed" do
    GitHub.cache.allow = /^flipper_/
    begin
      feature = create(:flipper_feature, name: "audit_log")
      feature.enable(@user)

      assert GitHub.flipper[:audit_log].enabled?(@user)

      feature.destroy
      refute GitHub.flipper[:audit_log].enabled?(@user)
    ensure
      GitHub.cache.allow = nil
    end
  end unless TestEnv.test_all_features?

  test "is in on state when fully enabled" do
    feature = create(:flipper_feature, name: "audit_log")

    assert_equal :off, feature.state
    feature.enable
    assert_equal :on, feature.state
    assert_predicate feature, :on?
  end

  test "is in off state when fully disabled" do
    feature = create(:flipper_feature, name: "audit_log")
    feature.enable

    assert_equal :on, feature.state
    feature.disable
    assert_equal :off, feature.state
    assert_predicate feature, :off?
  end

  test "features are disabled by default" do
    feature = create(:flipper_feature, name: "audit_log")
    refute feature.enabled?
    assert_predicate feature, :off?
  end

  test "can get actors" do
    feature = create(:flipper_feature, name: "audit_log")

    session = FlipperSession.new(1)
    host = GitHub::FlipperHost.new("example.xyz")

    feature.enable(@user)
    feature.enable(FlipperSession.new(1))
    feature.enable(GitHub::FlipperHost.new("example.xyz"))

    actors = feature.actors
    assert_equal 3, actors.size
    assert_includes actors, @user
    assert_includes actors, session
    assert_includes actors, host
  end

  test "can get actors safely when some have been deleted" do
    feature = create(:flipper_feature, name: "audit_log")

    feature.enable(@user)
    feature.enable(@staff)

    actors = feature.actors
    assert_equal 2, actors.size
    assert_includes actors, @user
    assert_includes actors, @staff

    @user.destroy
    feature = FlipperFeature.where(name: "audit_log").first
    assert_equal [@staff], feature.actors
  end

  test "returns actors that can be converted" do
    feature = create(:flipper_feature, name: "audit_log")

    feature.enable(Struct.new(:flipper_id).new("ThisIsNotAClass:1234"))
    feature.enable(@user)
    assert_equal [@user], feature.actors
  end

  test "can get actor ids by class" do
    feature = create(:flipper_feature, name: "audit_log")

    session = FlipperSession.new(1)
    host = GitHub::FlipperHost.new("example.xyz")

    feature.enable(@user)
    feature.enable(FlipperSession.new(1))
    feature.enable(GitHub::FlipperHost.new("example.xyz"))

    actor_ids_by_class = feature.actor_ids_by_class
    actor_classes = actor_ids_by_class.map(&:first)

    assert_equal 3, actor_classes.size
    assert_includes actor_classes, User
    assert_includes actor_classes, FlipperSession
    assert_includes actor_classes, GitHub::FlipperHost

    user_ids = actor_ids_by_class.find { |actor_class, _ids| actor_class == User }.second
    flipper_session_ids = actor_ids_by_class.find { |actor_class, _ids| actor_class == FlipperSession }.second
    github_flipper_host_ids = actor_ids_by_class.find { |actor_class, _ids| actor_class == GitHub::FlipperHost }.second

    assert_includes user_ids, @user.id.to_s
    assert_includes flipper_session_ids, session.id.to_s
    assert_includes github_flipper_host_ids, host.id.to_s
  end

  test "always_enabled? returns true if feature is enabled for an actor" do
    feature = create(:flipper_feature, name: "audit_log")
    feature.enable @user
    assert feature.always_enabled? @user
  end

  context "generate_context" do
    test "generates a proper closed context" do
      feature = create(:flipper_feature, name: :test)
      feature.enable_group("preview_features")
      context = feature.generate_context(@user)
      refute GitHub.flipper[:test].gates.any? { |gate| gate.open?(context) }
    end

    test "generates a proper open context" do
      feature = create(:flipper_feature, name: :test)
      feature.enable_group("preview_features")
      context = feature.generate_context(@staff)
      result = GitHub.flipper[:test].gates.any? { |gate| gate.open?(context) }
      if GitHub.enterprise?
        refute result
      else
        assert result
      end
    end
  end

  context "open_gates" do
    test "returns actor gates" do
      feature = create(:flipper_feature, name: "feature")
      feature.enable @user
      assert_equal feature.open_gates(@user).count, 1
      assert_equal feature.open_gates(@user).first.key, :actors
    end

    test "returns only boolean gates when there is one" do
      feature = create(:flipper_feature, name: "feature")
      feature.enable_percentage_of_time(100)
      feature.enable_percentage_of_actors(100)
      feature.enable_group("preview_features")
      feature.enable @staff
      feature.enable
      assert_equal feature.open_gates(@staff).count, 1
      assert_equal feature.open_gates(@staff).first.key, :boolean
    end

    test "returns group gates" do
      feature = create(:flipper_feature, name: "feature")
      feature.enable_group("preview_features")
      if GitHub.enterprise?
        assert_empty feature.open_gates(@staff)
      else
        assert_equal feature.open_gates(@staff).count, 1
        assert_equal feature.open_gates(@staff).first.key, :groups
      end
    end

    test "returns percentage_of_actors gates" do
      feature = create(:flipper_feature, name: "feature")
      feature.enable_percentage_of_actors(100)
      assert_equal feature.open_gates(@user).count, 1
      assert_equal feature.open_gates(@user).first.key, :percentage_of_actors
    end

    test "returns percentage_of_time gates" do
      feature = create(:flipper_feature, name: "feature")
      feature.enable_percentage_of_time(100)
      assert_equal feature.open_gates(@user).count, 1
      assert_equal feature.open_gates(@user).first.key, :percentage_of_time
    end

    test "returns multiple gates" do
      feature = create(:flipper_feature, name: "feature")
      feature.enable_percentage_of_time(100)
      feature.enable_percentage_of_actors(100)
      feature.enable_group("preview_features")
      feature.enable @staff

      expected_count = GitHub.enterprise? ? 3 : 4
      assert_equal feature.open_gates(@staff).count, expected_count
    end
  end

  test "current_visitor_actors_value only returns User::CurrentVisitorActor actors" do
    feature = create(:flipper_feature)
    feature.enable @user
    feature.enable FlipperSession.new(1)
    feature.enable GitHub::FlipperHost.new("example.xyz")
    feature.enable User::CurrentVisitorActor.new("GH.1.1234.5678")

    flipper_ids = [
      "User:#{@user.id}",
      "FlipperSession:1",
      "GitHub::FlipperHost:example.xyz",
      "User::CurrentVisitorActor:GH.1.1234.5678"
    ]
    assert_equal Set.new(flipper_ids), feature.actors_value
    assert_equal Set.new(["User::CurrentVisitorActor:GH.1.1234.5678"]), feature.current_visitor_actors_value
  end

  context ".fully_enabled_or_enabled_for_actor (scope)" do
    test "returns no duplicates" do
      feature = create(:flipper_feature, :always_enabled)
      feature.enable(@user)

      results = FlipperFeature.fully_enabled_or_enabled_for_actor(@user).to_a
      assert_equal results, results.uniq
    end

    test "applies a limit when provided as an argument" do
      always_enabled = create(:flipper_feature, :always_enabled)
      enabled_for_everyone = create(:flipper_feature, :enabled_for_everyone)

      results = FlipperFeature.where(id: [always_enabled, enabled_for_everyone])
        .fully_enabled_or_enabled_for_actor(@user, limit: 1).to_a
      assert_equal 1, results.size
    end

    test "includes features enabled 100% of the time" do
      feature = create(:flipper_feature, :always_enabled)
      assert_includes FlipperFeature.fully_enabled_or_enabled_for_actor(@user), feature
    end

    test "includes features enabled for 100% of actors" do
      feature = create(:flipper_feature, :enabled_for_everyone)
      assert_includes FlipperFeature.fully_enabled_or_enabled_for_actor(@user), feature
    end

    test "includes features enabled for a specific user" do
      feature = create(:flipper_feature)
      feature.enable(@user)
      assert_includes FlipperFeature.fully_enabled_or_enabled_for_actor(@user), feature
    end

    test "includes features enabled for a group a user belongs to" do
      user = create(:user, login: "adacat")
      Flipper.register(:adacats) do |actor|
        actor.respond_to?(:login) && actor.login.match(/adacat/)
      end unless Flipper.groups.map(&:name).include?(:adacats)

      feature = create(:flipper_feature)
      feature.enable_group :adacats

      assert feature.enabled?(user)
      assert_includes FlipperFeature.fully_enabled_or_enabled_for_actor(user), feature
    end

    test "excludes features not enabled for a user" do
      feature = create(:flipper_feature)
      refute_includes FlipperFeature.fully_enabled_or_enabled_for_actor(@user), feature
    end
  end

  context "fully_enabled?" do
    test "returns false for new features" do
      feature = create(:flipper_feature, name: "audit_log")
      refute_predicate feature, :fully_enabled?
    end

    test "returns true when enabled globally" do
      feature = create(:flipper_feature, name: "audit_log")
      feature.enable
      assert_predicate feature, :fully_enabled?
    end

    test "returns true when enabled 100% of the time" do
      feature = create(:flipper_feature, name: "audit_log")
      feature.enable_percentage_of_time(100)
      assert_predicate feature, :fully_enabled?
    end

    test "returns true when enabled for 100% of actors" do
      feature = create(:flipper_feature, name: "audit_log")
      feature.enable_percentage_of_actors(100)
      assert_predicate feature, :fully_enabled?
    end

    test "returns true when enabled for 100% of actors after disabling" do
      feature = create(:flipper_feature, name: "audit_log")
      feature.disable
      feature.enable_percentage_of_actors(100)
      assert_predicate feature, :fully_enabled?
    end

    test "returns false when disabled after enabling for 100% of actors" do
      feature = create(:flipper_feature, name: "audit_log")
      feature.enable_percentage_of_actors(100)
      feature.disable
      refute_predicate feature, :fully_enabled?
    end
  end

  context "fully_disabled?" do
    test "returns true for new features" do
      feature = create(:flipper_feature, name: "audit_log")
      assert_predicate feature, :fully_disabled?
    end

    test "returns false when enabled globally" do
      feature = create(:flipper_feature, name: "audit_log")
      feature.enable
      refute_predicate feature, :fully_disabled?
    end

    test "returns false when enabled 1% of the time" do
      feature = create(:flipper_feature, name: "audit_log")
      feature.enable_percentage_of_time(1)
      refute_predicate feature, :fully_disabled?
    end

    test "returns true when turned down to 0% of the time" do
      feature = create(:flipper_feature, name: "audit_log")
      feature.enable_percentage_of_time(1)
      feature.enable_percentage_of_time(0)
      assert_predicate feature, :fully_disabled?
    end

    test "returns false when enabled for 1% of actors" do
      feature = create(:flipper_feature, name: "audit_log")
      feature.enable_percentage_of_actors(1)
      refute_predicate feature, :fully_disabled?
    end

    test "returns true when turned down to 0% of actors" do
      feature = create(:flipper_feature, name: "audit_log")
      feature.enable_percentage_of_actors(1)
      feature.enable_percentage_of_actors(0)
      assert_predicate feature, :fully_disabled?
    end

    test "returns false when enabled for a group" do
      feature = create(:flipper_feature, name: "audit_log")
      feature.enable_group(:admins)
      refute_predicate feature, :fully_disabled?
    end

    test "returns true when all groups are removed" do
      feature = create(:flipper_feature, name: "audit_log")
      feature.enable_group(:admins)
      feature.enable_group(:dogs)
      feature.disable_group(:admins)
      refute_predicate feature, :fully_disabled?
      feature.disable_group(:dogs)
      assert_predicate feature, :fully_disabled?
    end

    test "returns false when enabled for an actor" do
      feature = create(:flipper_feature, name: "audit_log")
      feature.enable(create(:user))
      refute_predicate feature, :fully_disabled?
    end

    test "returns true when all actors are removed" do
      user1 = create(:user)
      user2 = create(:user)
      feature = create(:flipper_feature, name: "audit_log")
      feature.enable(user1)
      feature.enable(user2)
      feature.disable(user1)
      refute_predicate feature, :fully_disabled?
      feature.disable(user2)
      assert_predicate feature, :fully_disabled?
    end
  end

  context ".matches_name_or_description" do
    test "includes features with a matching name" do
      feature_1 = create(:flipper_feature, name: "matching_feature")
      feature_2 = create(:flipper_feature, name: "nope")

      matching_features = FlipperFeature.matches_name_or_description("match")

      assert_includes matching_features, feature_1
      refute_includes matching_features, feature_2
    end

    test "includes features with a matching description" do
      feature_1 = create(:flipper_feature, name: "feature_one", description: "this description is a good match")
      feature_2 = create(:flipper_feature, name: "feature_two", description: "nope")

      matching_features = FlipperFeature.matches_name_or_description("good")

      assert_includes matching_features, feature_1
      refute_includes matching_features, feature_2
    end
  end

  context ".github_org_team" do
    test "deleted team does not cause failed validation" do
      team = create(:team)
      FlipperFeature.stub_const(:GITHUB_ORG_ID, team.organization_id) do
        feature = create(:flipper_feature, github_org_team: team)
        team.destroy
        assert feature.update(name: feature.name + "_updated_with_deleted_team")
      end
    end
  end

  context "most_recent_gate_updated_at" do
    test "returns nil if feature has no gates" do
      feature = FlipperFeature.new
      assert_nil feature.most_recent_gate_updated_at
    end

    test "finds the most recent gate change" do
      feature = create(:flipper_feature)
      user_one = create(:user)
      user_two = create(:user)

      first_gate_added = "Wed, 26 Aug 2020 18:18:50 UTC +00:00".to_time
      second_gate_added = "Wed, 26 Aug 2020 18:28:50 UTC +00:00".to_time

      feature.flipper_gates.create(name: :actors, value: user_one.flipper_id, updated_at: first_gate_added)
      feature.flipper_gates.create(name: :actors, value: user_two.flipper_id, updated_at: second_gate_added)

      assert_equal second_gate_added, feature.most_recent_gate_updated_at
    end
  end

  unless GitHub.enterprise?
    context ".big_feature?" do
      test "returns true if listed in BIG_FEATURES list" do
        feature = create(:flipper_feature, name: ::Flipper::Config::BIG_FEATURES.first)
        assert_predicate feature, :big_feature?
      end

      test "returns false if not listed in BIG_FEATURES list" do
        feature = create(:flipper_feature, name: "foobar")
        refute_predicate feature, :big_feature?
      end
    end

    context ".show_big_feature_warning?" do
      test "returns true if feature is not on the list and has too many actors" do
        feature = create(:flipper_feature)
        feature.flipper_gates.create!(name: "actors", value: "User:1")

        ::Flipper::Config.stub_const(:BIG_FEATURES, ["another-feature"]) do
          FlipperFeature.stub_const(:BIG_FEATURE_WARNING_THRESHOLD, 0) do
            assert feature.show_big_feature_warning?
          end
        end
      end

      test "returns false if feature is not on the list but has too few actors" do
        feature = create(:flipper_feature)
        feature.flipper_gates.create!(name: "actors", value: "User:1")

        ::Flipper::Config.stub_const(:BIG_FEATURES, ["another-feature"]) do
          refute feature.show_big_feature_warning?
        end
      end

      test "returns false if feature is on the list and has too many actors" do
        feature = create(:flipper_feature)
        feature.flipper_gates.create!(name: "actors", value: "User:1")

        ::Flipper::Config.stub_const(:BIG_FEATURES, [feature.name]) do
          FlipperFeature.stub_const(:BIG_FEATURE_WARNING_THRESHOLD, 0) do
            refute feature.show_big_feature_warning?
          end
        end
      end

      test "returns false if feature is on the list and has too few actors" do
        feature = create(:flipper_feature)
        feature.flipper_gates.create!(name: "actors", value: "User:1")

        ::Flipper::Config.stub_const(:BIG_FEATURES, [feature.name]) do
          refute feature.show_big_feature_warning?
        end
      end
    end
  end
  test "supports emoji for description" do
    feature = create(:flipper_feature, description: "we ❤️ emojis")

    assert_multibyte_tracked_changes(feature, :description)
  end
end

class FlipperFeatureAuditingAndInstrumentationTest < GitHub::TestCase
  include AuditLogHelpers

  fixtures do
    @user = create :user, login: "guest"
  end

  test "feature.create is instrumented" do
    events = subscribe "feature.create"
    feature = create :flipper_feature, name: "audit_log"
    expected_payload = {
      feature_name: "audit_log",
      operation: :create,
    }

    assert event = events.pop, "expected feature.create event to be triggered"
    assert_equal expected_payload, event.payload
  end

  context "feature.update" do
    test "is instrumented when long_lived changes" do
      events = subscribe "feature.update"

      feature = create(:flipper_feature, name: "audit_log")
      feature.update(long_lived: true, description: "Some description")

      expected_payload = {
        feature_name: "audit_log",
        operation: :update,
        changes: {
          long_lived_was: false,
          long_lived: true
        }
      }

      refute_nil event = events.pop, "expected feature.update event to be triggered"
      assert_equal expected_payload, event.payload
    end

    test "is not instrumented when long_lived does not change" do
      events = subscribe "feature.update"

      feature = create(:flipper_feature, name: "audit_log")
      feature.update(description: "Some description")

      assert_nil events.pop, "expected no feature.update event to be triggered"
    end
  end

  test "feature.destroy is instrumented" do
    events = subscribe "feature.destroy"
    feature = create :flipper_feature, name: "audit_log"
    feature.destroy
    expected_payload = {
      feature_name: "audit_log",
      operation: :destroy,
    }

    assert event = events.pop, "expected feature.destroy event to be triggered"
    assert_equal expected_payload, event.payload
  end

  test "feature.enable is instrumented" do
    events = subscribe "feature.enable"

    feature = create(:flipper_feature, name: "audit_log")
    feature.enable @user

    event = events.pop
    assert event
    payload = event.payload
    assert_equal :audit_log, payload[:feature_name]
    assert_equal :enable, payload[:operation]
    assert_equal "guest", payload[:subject]
    assert_equal "User", payload[:subject_class]
    assert_equal @user.id, payload[:subject_id]
  end

  test "sends enable / disable events to audit log" do
    percentage = GitHub.flipper.actors(50)
    feature = create(:flipper_feature, name: "audit-log")
    feature.enable percentage
    feature.enable @user
    feature.disable @user

    Elastomer::Indexes::AuditLog.new.refresh

    options = {
      phrase: "action:feature.enable",
      index_name: Elastomer::Indexes::AuditLog.index_name,
      current_user: @user,
    }
    query = Audit::Driftwood::Query.new_stafftools_query(options)

    response = query.execute
    assert_equal 2, response.length
    found_actions = response.results.map { |hsh| hsh["action"] }
    assert_equal ["feature.enable", "feature.enable"], found_actions
  end

  test "sends notifications to Chatterbox for non-actor operations" do
    ENV["CHATTERBOX_TOKEN"] = "valid-token"
    percentage = GitHub.flipper.actors(50)
    GitHub::Chatterbox.client.expects(:say).at_least_once
    feature = create(:flipper_feature, name: "audit-log")
    feature.enable percentage
  end

  test "does not send notifications to Chatterbox for actor operations" do
    ENV["CHATTERBOX_TOKEN"] = "valid-token"
    percentage = GitHub.flipper.actors(50)
    GitHub::Chatterbox.client.expects(:say).never
    feature = create(:flipper_feature, name: "audit-log")
    feature.enable @user
    feature.disable @user
  end

  test "sends notifications to Chatterbox based on service name" do
    ENV["CHATTERBOX_TOKEN"] = "valid-token"
    GitHub::Chatterbox.client.expects(:say).once.with("github-features", " enabled the audit-log feature for 50% of actors")
    GitHub::Chatterbox.client.expects(:say).once.with("github-features-github-service1", " enabled the audit-log feature for 50% of actors")
    feature = create(:flipper_feature, name: "audit-log", service_name: "github/service1")
    feature.enable GitHub.flipper.actors(50)
  end

  test "replaces hyphens when looking for code references" do
    feature = create(:flipper_feature, name: "audit-log")
    mocked_grep = mock("GitHub::Grep")
    mocked_grep.expects(:code_use).with(/["':]audit_log/,
                              /audit_log_enabled\?/,
                              /audit_log_required/,
                              dirs: %w[app config jobs lib packages :(exclude)packages/*/test/* :(exclude)config/schema*.graphql]).returns([])

    GitHub::Grep.stubs(:new).returns(mocked_grep)
    assert_equal [], feature.code_usage
  end

  context "#get_subject_label" do
    test "returns nil if we don't want an actor" do
      assert_nil FlipperFeature.get_subject_label(gate_name: :actor, subject: :foo, skip_actor_gates: true)
    end

    test "returns expected string for a boolean gate" do
      assert_equal "everyone", FlipperFeature.get_subject_label(gate_name: :boolean, subject: :foo)
    end

    test "returns expected string for a percentage_of_time gate" do
      assert_equal "15% of enabled? calls", FlipperFeature.get_subject_label(gate_name: :percentage_of_time, subject: "15")
    end

    test "returns expected string for a percentage_of_actors gate" do
      assert_equal "15% of actors", FlipperFeature.get_subject_label(gate_name: :percentage_of_actors, subject: "15")
    end

    test "returns expected string for a group gate" do
      assert_equal "the feature_previews group", FlipperFeature.get_subject_label(gate_name: :group, subject: "feature_previews")
    end

    test "returns expected string for an actor gate" do
      user = create(:user)
      assert_equal user.to_s, FlipperFeature.get_subject_label(gate_name: :actor, subject: user.to_s)
    end

    test "returns expected string for a nil gate" do
      assert_equal "everyone", FlipperFeature.get_subject_label(gate_name: nil, subject: nil)
    end
  end

  context "batch_method :prelude_fully_enabled?" do
    test "batch loads flipper features by fully enabled status" do
      feature_boolean_on = create(:flipper_feature)
      feature_boolean_off = create(:flipper_feature)
      feature_actors_on = create(:flipper_feature)
      feature_time_on = create(:flipper_feature)

      feature_boolean_on.enable
      feature_actors_on.enable_percentage_of_actors(100)
      feature_time_on.enable_percentage_of_time(100)
      matrix = {
        feature_boolean_on => true,
        feature_boolean_off => false,
        feature_actors_on => true,
        feature_time_on => true,
      }
      GitHub::PrefillAssociations.prefill_batch_method(matrix.keys, :prelude_fully_enabled?)
      assert_query_count(0) do
        matrix.each do |feature, expected|
          assert_equal expected, feature.prelude_fully_enabled?
        end
      end
    end
  end

  context "batch_method :prelude_staff_shipped?" do
    test "batch loads flipper features by staff shipped status" do
      staff_shipped_feature = create(:flipper_feature)
      other_feature = create(:flipper_feature)

      staff_shipped_feature.enable_group(:preview_features)
      matrix = {
        staff_shipped_feature => true,
        other_feature => false,
      }
      GitHub::PrefillAssociations.prefill_batch_method(matrix.keys, :prelude_staff_shipped?)
      assert_query_count(0) do
        matrix.each do |feature, expected|
          assert_equal expected, feature.prelude_staff_shipped?
        end
      end
    end
  end

  context "batch_method :prelude_actor_or_percentage?" do
    test "batch loads flipper features by actor or percentage status" do
      feature_boolean_on = create(:flipper_feature)
      feature_actor = create(:flipper_feature)
      feature_actor_on = create(:flipper_feature)
      feature_actor_off = create(:flipper_feature)
      feature_actor_some = create(:flipper_feature)
      feature_staff_shipped = create(:flipper_feature)
      feature_group = create(:flipper_feature)

      feature_boolean_on.enable
      feature_actor.enable(@user)
      feature_actor_on.enable_percentage_of_actors(100)
      feature_actor_off.enable_percentage_of_actors(0)
      feature_actor_some.enable_percentage_of_actors(50)
      feature_staff_shipped.enable_group(:preview_features)
      feature_group.enable_group(:github_stars_members)

      matrix = {
        feature_boolean_on => false,
        feature_actor => true,
        feature_actor_on => false,
        feature_actor_off => false,
        feature_actor_some => true,
        feature_staff_shipped => false,
        feature_group => true,
      }
      GitHub::PrefillAssociations.prefill_batch_method(matrix.keys, :prelude_actor_or_percentage?)
      assert_query_count(0) do
        matrix.each do |feature, expected|
          assert_equal expected, feature.prelude_actor_or_percentage?
        end
      end
    end
  end

  context "#short_service_name" do
    test "when service name does not start with github/ returns service name" do
      service_name = "some-cool-service"
      short = build(:flipper_feature, service_name: service_name).short_service_name
      assert_equal service_name, short
    end

    test "when service name does start with github/ returns service name without prepeneded github" do
      service_name = "some-cool-service"
      short = build(:flipper_feature, service_name: "github/#{service_name}").short_service_name
      assert_equal service_name, short
    end
  end

  context "#short_tracking_issue_url" do
    test "removes github.com from issue url" do
      assert_equal "foo",
        build(:flipper_feature, tracking_issue_url: "https://github.com/foo").short_tracking_issue_url
    end

    test "shortens the link for issues" do
      assert_equal "github/github#123",
        build(:flipper_feature, tracking_issue_url: "https://github.com/github/github/issues/123").short_tracking_issue_url
    end

    test "shortens the link for prs" do
      assert_equal "github/github#123",
        build(:flipper_feature, tracking_issue_url: "https://github.com/github/github/pull/123").short_tracking_issue_url
    end

    test "shortens the link for discussions" do
      assert_equal "github/github#123",
        build(:flipper_feature, tracking_issue_url: "https://github.com/github/github/discussions/123").short_tracking_issue_url
    end

    test "handles when a repo is also one of our nouns" do
      assert_equal "github/issues#123",
        build(:flipper_feature, tracking_issue_url: "https://github.com/github/issues/issues/123").short_tracking_issue_url
    end
  end

  context "#stale?" do
    test "returns true if the feature is stale and not long lived" do
      assert_predicate build(:flipper_feature, stale_at: 1.year.ago), :stale?
    end

    test "returns false if the feature is long_lived" do
      refute_predicate build(:flipper_feature, long_lived: true, stale_at: nil), :stale?
    end

    test "returns false if the feature is not long lived and not stale" do
      refute_predicate build(:flipper_feature, stale_at: 1.year.from_now), :stale?
    end
  end

  context "concurrency validation" do
    test "writes fails if mismatch rollout_updated_at" do
      # "db"'s rollout_updated_at will be set to 10 minutes ago
      feature = create(:flipper_feature, rollout_updated_at: Time.new - 10.minutes)
      feature.rollout_updated_at = Time.now
      feature.instance_variable_set(:@should_compare_etag, true)

      assert_raises Flipper::Adapters::Mysql::ConcurrencyError do
        feature.enable
      end
    end

    test "writes succeeds if rollout_updated_at matches" do
      feature = create(:flipper_feature, rollout_updated_at: Time.new)
      feature.instance_variable_set(:@should_compare_etag, true)

      assert_nothing_raised do
        feature.enable
      end
    end

    test "if not given should_compare_etag then don't compare rollout_updated_at" do
      # "db"'s rollout_updated_at will be set to 10 minutes ago
      feature = create(:flipper_feature, rollout_updated_at: Time.new - 10.minutes)
      feature.rollout_updated_at = Time.now
      # note the lack of @should_compare_etag

      assert_nothing_raised do
        feature.enable
      end
    end

  end

  context "shared_gates" do
    test "returns shared gates" do
      feature = create(:flipper_feature)
      boolean_gate = create(:flipper_gate, name: "boolean", flipper_feature_id: feature.id)
      actor_gate = create(:flipper_gate, name: "actors", flipper_feature_id: feature.id)
      percentage_of_actor_gate = create(:flipper_gate, name: "percentage_of_actors", flipper_feature_id: feature.id)
      percentage_of_time_gate = create(:flipper_gate, name: "percentage_of_time", flipper_feature_id: feature.id)
      group_gate = create(:flipper_gate, name: "groups", flipper_feature_id: feature.id)

      result = feature.shared_gates.sort_by(&:id)
      assert_equal(result, [boolean_gate, percentage_of_actor_gate, percentage_of_time_gate, group_gate])
    end
  end
end
