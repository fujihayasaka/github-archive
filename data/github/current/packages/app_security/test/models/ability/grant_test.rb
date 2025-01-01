# typed: false
# frozen_string_literal: true

require "test_helper"
require "test_helpers/ability_models"

class AbilityGrantTest < GitHub::TestCase
  setup do
    @actor     = AnActor.create
    @connector = AnActorAndSubject.create
    @subject   = ASubject.create
  end

  test "noops if the ability already exists" do
    original = grant(@actor, :read, @subject)
    assert_able @actor, :read, @subject

    assert_no_new_abilities do
      dup = grant(@actor, :read, @subject)
      assert_equal original, dup
    end
  end

  test "updates the existing ability if actions differ" do
    original = grant(@actor, :read, @subject)

    assert_no_new_abilities do
      dup = grant(@actor, :write, @subject)
      assert_able @actor, :write, @subject
    end
  end

  test "retries to create the ability if the existing ability was deleted before trying to update" do
    original = grant(@actor, :read, @subject)

    grant = Ability::Grant.new(@actor, :write, @subject)

    # remove existing record before it can be updated, after it prevented a
    # duplicate from being created, reproducing the race.
    def grant.find_existing_direct_ability(actor, subject)
      existing = super
      @existing_destroyed = existing.destroy
      nil
    end

    result = grant.apply

    assert grant.instance_variable_get(:@existing_destroyed)

    assert_able @actor, :write, @subject
    refute_equal original.id, result.id
  end

  test "updates the existing ability if actions are different" do
    original = grant(@actor, :read, @subject)
    grant = Ability::Grant.new(@actor, :write, @subject)
    grant.apply
    assert_able @actor, :write, @subject
  end

  test "grants admin permission on the subject" do
    refute_able @actor, :admin, @subject
    grant = Ability::Grant.new(@actor, :admin, @subject)
    result = grant.apply
    assert_able @actor, :admin, @subject
  end

  test "raises after retrying to create the ability a second time fails" do
    original = grant(@actor, :read, @subject)

    grant = Ability::Grant.new(@actor, :write, @subject)

    # pretend the existing ability was deleted, but it wasn't so we force a
    # repeat duplicate scenario
    def grant.find_existing_direct_ability(actor, subject)
      nil
    end

    assert_raises ActiveRecord::RecordNotUnique do
      result = grant.apply
    end
  end

  test "creates dependants when the actor is a connector" do
    first    = grant(@connector, :read, @subject)
    second   = grant(@actor, :admin, @connector)
    dependant = Authorization.service.most_capable_ability_between(actor: @actor, subject: @subject)

    refute_nil dependant
    assert dependant.read?

    assert_equal first.id, dependant.parent_id
    assert_equal second.id, dependant.grandparent_id
  end

  test "sets the grantor attribute when initialized with a grantor" do
    grantor = AnActor.new
    grant = Ability::Grant.new(AnActor.new, :read, ASubject.new, grantor: grantor)

    assert_equal grant.grantor, grantor
  end

  test "sets the ability's grantor_id to the grantor's id when applied with a grantor" do
    grant = Ability::Grant.new(@actor, :read, @subject, grantor: @actor)
    assert ability = grant.apply

    assert_equal ability.grantor_id, @actor.id
  end

  test "does not set the ability's grantor_id when applied without a grantor" do
    grant = Ability::Grant.new(@actor, :read, @subject)
    assert ability = grant.apply

    assert_nil ability.grantor_id
  end

  test "granting abilities uses throttle_with_retry" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    # simulate nested team
    top = AnActorAndSubject.create
    bottom = AnActorAndSubject.create
    bottom.ancestors = [top]

    Ability.throttler.stubs(:throttle).raises(Freno::Throttler::Error)

    # the thottling is triggered for cascading abilities
    err = assert_raises Freno::Throttler::Error do
      Ability::Grant.stub_const(:THROTTLE_RETRIES, 1) do
        Ability.stub_const(:BATCH_SIZE, 1) do
          bottom.grant @actor, :read
        end
      end
    end

    assert_equal "Throttler timed out after retrying 1 times. Called from Ability::Grant#apply_abilities", err.message
  end

  test "updates dependants when the actor is a connector" do
    grant(@connector, :read, @subject)
    grant(@actor, :admin, @connector)

    assert_able @actor, :read, @subject
    refute_able @actor, :write, @subject

    assert_no_new_abilities do
      grant(@connector, :write, @subject)
      assert_able @actor, :write, @subject
    end
  end

  test "creates dependants when the subject is a connector" do
    first    = grant(@actor, :admin, @connector)
    second   = grant(@connector, :read, @subject)
    dependant = Authorization.service.most_capable_ability_between(actor: @actor, subject: @subject)

    refute_nil dependant
    assert dependant.read?

    # parent contributes the derived ability's action
    assert_equal second.id, dependant.parent_id
    assert_equal first.id, dependant.grandparent_id
  end

  test "nearest ability to a subject when granted first defines an dependant ability's action" do
    # subject grant
    grant @connector, :write, @subject
    # then actor
    grant @actor, :read, @connector
    assert_able @actor, :write, @subject
  end

  test "nearest ability to a subject when granted last defines an dependant ability's action" do
    # actor grant
    grant @actor, :read, @connector
    # then subject
    grant @connector, :write, @subject
    assert_able @actor, :write, @subject
  end

  test "updates dependants when the subject is a connector" do
    grant(@actor, :admin, @connector)
    grant(@connector, :read, @subject)

    assert_able @actor, :read, @subject
    refute_able @actor, :write, @subject

    assert_no_new_abilities do
      grant(@connector, :write, @subject)
      assert_able @actor, :write, @subject
    end
  end

  test "blows up when the actor and the subject are both connectors" do
    another_connector = AnActorAndSubject.create

    ex = assert_raises RuntimeError do
      grant(@connector, :read, another_connector)
    end

    msg = "AnActorAndSubject -> AnActorAndSubject grants aren't allowed"
    assert_equal msg, ex.message
  end

  test "grants admin permission on the subject's dependents" do
    parent = AParent.create(dependents: [@subject])
    admin = parent.grant(@actor, :admin)

    assert_able @actor, :admin, @subject

    dependant = Authorization.service.most_capable_ability_between(actor: @actor, subject: @subject)
    assert_equal admin.id, dependant.parent_id
  end

  test "propagates update to admin grant to subject's dependents" do
    parent = AParent.create(dependents: [@subject])
    parent.grant @actor, :read

    refute_able @actor, :admin, @subject
    admin = parent.grant @actor, :admin

    assert_able @actor, :admin, @subject

    dependant = Authorization.service.most_capable_ability_between(actor: @actor, subject: @subject)
    assert_equal admin.id, dependant.parent_id
  end

  test "revokes permission to subject's dependents when downgrading from admin" do
    parent = AParent.create(dependents: [@subject])
    parent.grant @actor, :admin

    assert_able @actor, :admin, @subject
    parent.grant @actor, :read

    refute_able @actor, :admin, @subject
  end

  test "preserves normal dependants when downgrading from admin" do
    @connector.grant @actor, :read
    @subject.grant @connector, :admin
    assert_able @actor, :admin, @subject

    @subject.grant @connector, :read
    assert_able @actor, :read, @subject
    refute_able @actor, :admin, @subject
  end

  test "only updates an dependant ability if the closest ability to the subject is changed" do
    @connector.grant @actor, :read
    @subject.grant @connector, :write
    assert_able @actor, :write, @subject

    @connector.grant @actor, :admin
    refute_able @actor, :admin, @subject
    assert_able @actor, :write, @subject
  end

  # Materializing indirect abilities has a restricted applicability to nested teams.
  # Perhaps in the future we want to generalize that for other types of subjects, but
  # that's not the case now.
  context "materialized indirect abilities (only for Team subjects)" do

    test "creates materialized indirect abilities on ancestors " do
      org = create :organization, plan: "bronze"

      team_employees   = create :team, organization: org, privacy: :closed, name: "employees"
      team_marketing   = create :team, organization: org, privacy: :closed, name: "marketing",   parent_team_id: team_employees.id
      team_engineering = create :team, organization: org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
      team_identity    = create :team, organization: org, privacy: :closed, name: "identity",    parent_team_id: team_engineering.id

      user = create(:user)
      Ability::Grant.new(user, :read, team_identity).apply

      direct = Authorization.service.most_capable_ability_between(actor: user, subject: team_identity)
      assert direct.direct?
      assert direct.read?

      [team_engineering, team_employees].each do |team|
        indirect = Authorization.service.most_capable_ability_between(actor: user, subject: team)
        assert indirect.indirect?
        assert indirect.read?
        assert_equal direct.id, indirect.parent_id
      end

      assert_nil Authorization.service.most_capable_ability_between(actor: user, subject: team_marketing)
    end

    test "updates materialized indirect abilities if action changes" do
      org = create :organization, plan: "bronze"

      team_employees   = create :team, organization: org, privacy: :closed, name: "employees"
      team_marketing   = create :team, organization: org, privacy: :closed, name: "marketing",   parent_team_id: team_employees.id
      team_engineering = create :team, organization: org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
      team_identity    = create :team, organization: org, privacy: :closed, name: "identity",    parent_team_id: team_engineering.id

      user = create(:user)
      Ability::Grant.new(user, :read, team_identity).apply
      read = Authorization.service.most_capable_ability_between(
        actor: user,
        subject: team_engineering,
      )
      assert read.read?

      # We grant access again, but with a different action
      Ability::Grant.new(user, :write, team_identity).apply
      direct = Authorization.service.most_capable_ability_between(actor: user, subject: team_identity)
      assert direct.direct?
      assert direct.write?

      [team_engineering, team_employees].each do |team|
        indirect = Authorization.service.most_capable_ability_between(actor: user, subject: team)
        assert indirect.indirect?
        assert indirect.read?
        assert_equal direct.id, indirect.parent_id
      end
    end
  end

  def assert_no_new_abilities(&block)
    assert_no_difference -> { Ability.where(priority: [Ability.priorities[:direct], Ability.priorities[:indirect]]).count } do
      yield
    end
  end

  def grant(actor, action, subject)
    Ability::Grant.new(actor, action, subject).apply
  end
end
