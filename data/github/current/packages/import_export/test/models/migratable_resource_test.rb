# typed: true
# frozen_string_literal: true

require "test_helper"

class MigratableResourceTest < GitHub::TestCase
  fixtures do
    @guid = "import-t1-o1"

    @migratable_resource = create(
      :migratable_resource,
      guid: @guid,
      model_type: "user",
      source_url: "http://github.dev/test_user",
      state: MigratableResource.states[:export]
    )
  end

  test "in progress is true when a given guid's resource states are not all in FINAL_STATES" do
    @migratable_resource.update_attribute(:state, MigratableResource.states[:export])

    assert_predicate MigratableResource.for_guid(@guid), :in_progress?
  end

  test "in progress is false when a given guid's resource states are all in FINAL_STATES" do
    @migratable_resource.update_attribute(:state, MigratableResource::FINAL_STATES.first)

    refute_predicate MigratableResource.for_guid(@guid), :in_progress?
  end

  context "#succeeded?" do
    test "should return true for all states in SUCCEEDED_STATES" do
      MigratableResource::SUCCEEDED_STATES.each do |state|
        @migratable_resource.state = state
        assert @migratable_resource.succeeded?
      end
    end

    test "should return false for states that aren't in SUCCEEDED_STATES" do
      other_states = MigratableResource.states.keys - MigratableResource::SUCCEEDED_STATES

      other_states.each do |state|
        @migratable_resource.state = state
        refute @migratable_resource.succeeded?
      end
    end
  end

  context "#failed?" do
    test "should return true for all states in FAILED_STATES" do
      MigratableResource::FAILED_STATES.each do |state|
        @migratable_resource.state = state
        assert @migratable_resource.failed?
      end
    end

    test "should return false for states that aren't in FAILED_STATES" do
      other_states = MigratableResource.states.keys - MigratableResource::FAILED_STATES

      other_states.each do |state|
        @migratable_resource.state = state
        refute @migratable_resource.failed?
      end
    end
  end

  context "#should_map?" do
    test "with model it returns true" do
      user = create(:user)
      @migratable_resource.update_attribute(:state, MigratableResource.states[:map])

      assert @migratable_resource.should_map?(user)
    end

    test "with nil it returns false" do
      @migratable_resource.update_attribute(:state, MigratableResource.states[:map])

      refute @migratable_resource.should_map?(nil)
    end
  end

  context "#should_import?" do
    test "with model it returns false" do
      user = create(:user)
      @migratable_resource.update_attribute(:state, MigratableResource.states[:import])

      refute @migratable_resource.should_import?(user)
    end

    test "with nil it returns true" do
      @migratable_resource.update_attribute(:state, MigratableResource.states[:import])

      assert @migratable_resource.should_import?(nil)
    end
  end

  context "#should_merge?" do
    test "with model it returns true" do
      team = create(:team)
      @migratable_resource.update_attribute(:state, MigratableResource.states[:merge])

      assert @migratable_resource.should_merge?(team)
    end

    test "with nil it returns false" do
      @migratable_resource.update_attribute(:state, MigratableResource.states[:merge])

      refute @migratable_resource.should_merge?(nil)
    end
  end

  context "#models_for_migratable_resources" do
    test "should return models when scope is given" do
      users = [
        create(:user, { email: "foo1@example.com", login: "dood1", password: GitHub.default_password }),
        create(:user, { email: "foo2@example.com", login: "dood2", password: GitHub.default_password }),
        create(:user, { email: "foo3@example.com", login: "dood3", password: GitHub.default_password }),
        create(:user, { email: "foo4@example.com", login: "dood4", password: GitHub.default_password }),
      ]

      migratable_resources = users.map do |user|
        create :migratable_resource, guid: @guid, model_type: "user", source_url: "http://github.dev/#{user.login}", model_id: user.id
      end

      models = MigratableResource.models_for_migratable_resources(migratable_resources, scope: User.includes(:profile))
      assert_same_elements users, models
    end

    test "should return models when scope is not given" do
      users = [
        create(:user, { email: "foo1@example.com", login: "dood1", password: GitHub.default_password }),
        create(:user, { email: "foo2@example.com", login: "dood2", password: GitHub.default_password }),
        create(:user, { email: "foo3@example.com", login: "dood3", password: GitHub.default_password }),
        create(:user, { email: "foo4@example.com", login: "dood4", password: GitHub.default_password }),
      ]

      migratable_resources = users.map do |user|
        create :migratable_resource, guid: @guid, model_type: "user", source_url: "http://github.dev/#{user.login}", model_id: user.id
      end

      models = MigratableResource.models_for_migratable_resources(migratable_resources)
      assert_same_elements users, models
    end

    test "should raise exception if migratable_resources don't have the same model type" do
      user = create(:user, { email: "foo1@example.com", login: "dood1", password: GitHub.default_password })
      org = create(:organization, login: "peoples", admin: user)

      models_to_migrate = [
        user,
        create(:user, { email: "foo2@example.com", login: "dood2", password: GitHub.default_password }),
        create(:user, { email: "foo3@example.com", login: "dood3", password: GitHub.default_password }),
        create(:user, { email: "foo4@example.com", login: "dood4", password: GitHub.default_password }),
        create(:repository, owner: org, name: "hub"),
      ]

      migratable_resources = models_to_migrate.map do |model|
        create :migratable_resource, guid: @guid, model_type: model.class.name.downcase, source_url: "http://github.dev/#{model.class.name.downcase.pluralize}/#{model.id}", model_id: model.id
      end

      e = assert_raises(RuntimeError) do
        MigratableResource.models_for_migratable_resources(migratable_resources)
      end
      assert_equal "migratable resources must have same model_type", e.message
    end

    test "should not raise exception if model tied to migratable resource was deleted when scope is given"  do
      org = create(:organization, login: "peoples")
      repo = create(:repository, owner: org, name: "hub")
      issue_1 = create(:issue, repository: repo)
      issue_2 = create(:issue, repository: repo)
      issue_3 = create(:issue, repository: repo)

      issues = [issue_1, issue_2, issue_3]

      migratable_resources = issues.map do |issue|
        create :migratable_resource, guid: @guid, model_type: "issue", source_url: "http://github.dev/#{org.login}/#{repo.name}/issues/#{issue.number}", model_id: issue.id
      end

      # destroy the first issue
      issue_1.try(:destroy)

      models = MigratableResource.models_for_migratable_resources(migratable_resources, scope: GitHub::Migrator::IssueSerializer.new.scope)
      assert_same_elements [issue_2, issue_3], models
    end

    test "should not raise exception if model tied to migratable resource was deleted when scope is not given"  do
      org = create(:organization, login: "peoples")
      repo = create(:repository, owner: org, name: "hub")
      issue_1 = create(:issue, repository: repo)
      issue_2 = create(:issue, repository: repo)
      issue_3 = create(:issue, repository: repo)

      issues = [issue_1, issue_2, issue_3]

      migratable_resources = issues.map do |issue|
        create :migratable_resource, guid: @guid, model_type: "issue", source_url: "http://github.dev/#{org.login}/#{repo.name}/issues/#{issue.number}", model_id: issue.id
      end

      # destroy the first issue
      issue_1.try(:destroy)

      models = MigratableResource.models_for_migratable_resources(migratable_resources)
      assert_same_elements [issue_2, issue_3], models
    end

    test "should not raise exception if no models are found"  do
      org = create(:organization, login: "peoples")
      repo = create(:repository, owner: org, name: "hub")
      issue_1 = create(:issue, repository: repo)
      issue_2 = create(:issue, repository: repo)
      issue_3 = create(:issue, repository: repo)

      issues = [issue_1, issue_2, issue_3]

      migratable_resources = issues.map do |issue|
        create :migratable_resource, guid: @guid, model_type: "issue", source_url: "http://github.dev/#{org.login}/#{repo.name}/issues/#{issue.number}", model_id: issue.id
      end

      # destroy the first issue
      issue_1.try(:destroy)
      issue_2.try(:destroy)
      issue_3.try(:destroy)

      models = MigratableResource.models_for_migratable_resources(migratable_resources)
      assert_empty models
    end

    test "should return team models in the same order as migratable_resources" do
      teams = [
        create(:team, { name: "team1" }),
        create(:team, { name: "team2" }),
        create(:team, { name: "team3" }),
        create(:team, { name: "team4" }),
      ]
      shuffled_teams = teams.dup.shuffle(random: Random.new(1))
      migratable_resources = shuffled_teams.map do |team|
        create :migratable_resource, guid: @guid, model_type: "team", source_url: "http://github.dev/#{team.name}", model_id: team.id
      end

      models = MigratableResource.models_for_migratable_resources(migratable_resources, scope: Team.includes(:organization))

      assert_equal shuffled_teams.pluck(:id), models.pluck(:id)
      refute_equal teams.pluck(:id), models.pluck(:id)
      assert_same_elements teams.pluck(:id), models.pluck(:id)
    end
  end
end
