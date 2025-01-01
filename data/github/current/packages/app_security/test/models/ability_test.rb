# typed: false
# frozen_string_literal: true

require "test_helper"
require "test_helpers/ability_models"

class AbilityTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @actor     = AnActor.create
    @actor2    = AnActor.create
    @subject   = ASubject.create
    @cascader  = AnActorAndSubject.create
    @cascader2 = AnActorAndSubject.create
    @child     = ASubject.create
    @parent    = AParent.create

    @triage_user = create :user
    @maintain_user = create :user
    @org_on_business_plus = create :business_plus_organization
    @org_repo = create :repository, :minimal, owner: @org_on_business_plus
  end

  context "valid_action?" do
    test "true for a valid action in symbol form" do
      assert Ability.valid_action?(:read)
    end

    test "true for a valid action in string form" do
      assert Ability.valid_action?("read")
    end

    test "false for an invalid action" do
      refute Ability.valid_action?(:invalid)
    end

    test "false for nil" do
      refute Ability.valid_action?(nil)
    end
  end

  context "async_can?" do
    test "returns a promise that resolves to a boolean" do
      promise = Ability.async_can?(@actor, :admin, @actor)

      assert_kind_of ::Promise, promise
      assert_equal true, promise.sync
    end
  end

  test "actor can admin itself" do
    assert Ability.can?(@actor, :admin, @actor)
  end

  test "actor can do nothing to subject without an ability relationship" do
    refute_able @actor, :read, @subject
    refute_able @actor, :write, @subject
    refute_able @actor, :admin, @subject
  end

  test "nil actor cannot act on any subject" do
    refute_able nil, :read, @subject
  end

  test "actors cannot act on a nil subject" do
    refute_able @actor, :read, nil
  end

  context "#bulk_grant" do
    test "actors are granted an ability using grant bulk method" do
      refute_able @actor, :read, @subject
      refute_able @actor2, :read, @subject

      Ability.bulk_grant [@actor, @actor2], :read, @subject

      assert_able @actor, :read, @subject
      assert_able @actor2, :read, @subject
    end
  end

  test "actors which are missing an ability_id cannot act on a subject" do
    @subject.grant @actor, :read

    def @actor.ability_id
      nil
    end

    refute_able @actor, :read, @subject
  end

  test "actors cannot act on a subject which is missing an ability id" do
    @subject.grant @actor, :read

    def @subject.ability_id
      nil
    end

    refute_able @actor, :read, @subject
  end

  test "lower actions do not include higher ones" do
    @subject.grant @actor, :read

    refute_able @actor, :write, @subject
    refute_able @actor, :admin, @subject

    @subject.grant @actor, :write
    refute_able @actor, :admin, @subject
  end

  test "higher actions include lower ones" do
    @subject.grant @actor, :admin

    assert_able @actor, :read, @subject
    assert_able @actor, :write, @subject
    assert_able @actor, :admin, @subject

    @subject.revoke @actor
    @subject.grant @actor, :write

    assert_able @actor, :read, @subject
    assert_able @actor, :write, @subject
    refute_able @actor, :admin, @subject
  end

  test "granting and revoking an ability leaves no ability" do
    refute_able @actor, :read, @subject

    @subject.grant @actor, :read
    assert_able @actor, :read, @subject

    @subject.revoke @actor
    refute_able @actor, :read, @subject
  end

  test "re-granting an existing ability results in the last ability" do
    @subject.grant @actor, :admin
    assert_able @actor, :admin, @subject

    @subject.grant @actor, :write
    refute_able @actor, :admin, @subject
    assert_able @actor, :write, @subject
  end

  test "re-granting the same direct ability re-uses the record" do
    entry = @subject.grant @actor, :read
    new_entry = @subject.grant(@actor, :read)
    assert_equal entry.id, new_entry.id
  end

  test "#delete_dependent_abilities_for defaults to enqueueing a GitHub::Jobs::DeleteDependentAbilities job" do
    direct = @subject.grant @cascader, :write
    @cascader.grant @actor, :write

    assert_enqueued_jobs 1, only: DeleteDependentAbilitiesJob, queue: "delete_dependent_abilities" do
      Ability.delete_dependent_abilities_for(direct.id)
    end

    assert_enqueued_with(job: DeleteDependentAbilitiesJob, args: [[direct.id]], queue: "delete_dependent_abilities")
  end

  test "#delete_dependent_abilities_for! throttles each batch of dependent abilities" do
    @cascader2.ancestors = [@cascader]
    parent_ability = @cascader2.grant @actor, :read

    # The should be only one materialized indirect ability between @actor and @cascader via @cascader2
    Ability.stub_const(:BATCH_SIZE, 1) do
      GitHub::Throttler::Null.any_instance.expects(:throttle).times(1)
      Ability.delete_dependent_abilities_for! parent_ability.id
    end
  end

  test "favor the best indirect ability if only indirect is present" do
    # ordering matters: read gets cascaded last
    @subject.grant @cascader, :write
    @subject.grant @cascader2, :read
    @cascader.grant @actor, :write
    @cascader2.grant @actor, :read

    assert_able @actor, :write, @subject
  end

  test "admin ability on a parent supercedes direct grants on children" do
    # Example scenario in comments
    #
    # parent is an org, child is a repo in the org
    @parent.dependents = [@child]

    # grant actor admin on the parent (org)
    @parent.grant @actor, :admin

    # grant actor read on the repo (child)
    @child.grant @actor, :read

    assert_able @actor, :admin, @child
  end

  test "direct abilities can cascade to subjects" do
    @subject.grant @cascader, :read
    @cascader.grant @actor, :read
    assert_able @actor, :read, @subject
  end

  test "removes cascading permissions on dependent when admin is downgraded" do
    @parent.dependents = [@child]

    @parent.grant @actor, :admin
    assert_able @actor, :admin, @child
    @parent.grant @actor, :read
    assert_able @actor, :read, @parent
    refute_able @actor, :admin, @parent
    refute_able @actor, :read, @child
  end

  test "adjusts indirect grants when the related direct grants change" do
    @subject.grant @cascader, :read
    @cascader.grant @actor, :read
    @subject.grant @cascader, :write
    assert_able @actor, :write, @subject
  end

  test "cascades the subject's action" do
    @subject.grant @cascader, :write
    @cascader.grant @actor, :read
    assert_able @actor, :write, @subject
  end

  test "cascades the subject's action, even when it's weaker" do
    @subject.grant(@cascader, :read)
    @cascader.grant @actor, :admin
    assert_able @actor, :read, @subject
    refute_able @actor, :admin, @subject
  end

  test "abilities cascade to actors" do
    @cascader.grant @actor, :read
    @subject.grant @cascader, :write

    assert_able @actor, :write, @subject
  end

  test "admin abilities cascade to children" do
    @parent.dependents = [@child]

    @parent.grant @actor, :admin
    assert_able @actor, :admin, @child
  end

  test "updated subject permissions cascade upward" do
    @cascader.grant @actor, :read
    @subject.grant @cascader, :write

    assert_able @actor, :write, @subject

    @subject.grant @cascader, :read # replace write with read
    refute_able @cascader, :write, @subject
    assert_able @cascader, :read, @subject

    refute_able @actor, :write, @subject
    assert_able @actor, :read, @subject
  end

  test "updated actor permissions do not cascade downward" do
    @cascader.grant @actor, :write
    @subject.grant @cascader, :read

    assert_able @actor, :read, @subject
    refute_able @actor, :write, @subject

    @cascader.grant @actor, :admin # replace write with admin
    assert_able @actor, :read, @subject
    refute_able @actor, :write, @subject
    refute_able @actor, :admin, @subject
  end

  test "revocation of subject's ability cascades" do
    @cascader.grant @actor, :read
    @subject.grant @cascader, :read

    assert_able @actor, :read, @subject

    @subject.revoke @cascader
    refute_able @actor, :read, @subject
  end

  test "cascading revocation cleans up the family tree" do
    @cascader.grant @actor, :read
    @subject.grant @cascader, :read

    @subject.revoke @cascader
    refute_able @actor, :read, @subject
  end

  test "revoke also revokes ability which granted indirect permissions via subject cascade" do
    @subject.grant @cascader, :write
    @cascader.grant @actor, :read

    @subject.revoke @cascader

    refute_able @actor, :write, @subject
  end

  test "revoke also revokes indirect abilities cascaded to actors" do
    @cascader.grant @actor, :read
    @subject.grant @cascader, :write
    @cascader.grant @actor, :read
    @cascader.revoke @actor

    refute_able @actor, :write, @subject
  end

  test "revoking part of cascade revokes abilities cascaded to actors" do
    @cascader.grant @actor, :read
    @subject.grant @cascader, :write
    @subject.revoke @cascader

    refute_able @actor, :write, @subject
  end

  test "preserves preexisting indirect grants on revocation of subject cascades" do
    middle = AnActorAndSubject.create
    parent = AParent.create(dependents: [middle])

    @subject.grant middle, :read
    middle.grant @actor, :read
    assert_able @actor, :read, @subject

    parent.grant @actor, :read
    parent.revoke @actor
    assert_able @actor, :read, @subject
  end

  test "#clear defaults to enqueueing a GitHub::Job::ClearAbilities job" do
    @cascader.grant @actor, :read

    assert_enqueued_jobs 1, only: ClearAbilitiesJob, queue: "clear_abilities" do
      Ability.clear @cascader
    end

    assert_enqueued_with(job: ClearAbilitiesJob, args: [@cascader.id, @cascader.ability_type], queue: "clear_abilities")
  end

  test "#clear calls .clear! inline if async is false" do
    @cascader.grant @actor, :read

    Ability.expects(:clear!)

    Ability.clear @cascader, async: false

    assert_enqueued_jobs 0, only: ClearAbilitiesJob, queue: :clear_abilities
  end

  test "#clear! throttles its queries" do
    @cascader.grant @actor, :read

    GitHub::Throttler::Null.any_instance.expects(:throttle).once

    participant = @cascader.ability_delegate
    Ability.clear!(participant.ability_id, participant.ability_type)
  end

  test "#clear! throttles each batch of direct ability deletes" do
    @cascader.grant @actor, :read
    @subject.grant @cascader, :read

    # There should be two direct abilities in this scenario:
    # 1. Direct between @cascader and @actor
    # 2. Direct between @subject and @cascader
    #
    # Note: There should be *NO* dependent abilities, otherwise the call to
    # delete_dependent_abilities_for! will also call the throttler.
    participant = @cascader.ability_delegate
    Ability.stub_const(:BATCH_SIZE, 1) do
      GitHub::Throttler::Null.any_instance.expects(:throttle).yields(nil).times(2)
      Ability.clear!(participant.ability_id, participant.ability_type)
    end
  end

  test "#clear! throttles each batch of materialized indirect ability deletes" do
    @cascader2.ancestors = [@cascader]
    parent_ability = @cascader2.grant @actor, :read

    assert_able @actor, :read, @cascader2
    assert_able @actor, :read, @cascader

    # The throttler should be called 2 times because of 2 abilities:
    # 1. a direct ability between @actor and @cascader2
    # 2. an indirect ability between @actor and @cascader
    participant = @cascader2.ability_delegate
    Ability.stub_const(:BATCH_SIZE, 1) do
      GitHub::Throttler::Null.any_instance.expects(:throttle).yields(nil).times(2)
      Ability.clear!(participant.ability_id, participant.ability_type)
    end

    refute_able @actor, :read, @cascader2
    refute_able @actor, :read, @cascader
  end

  test "remove all abilities on a participant" do
    @cascader.grant @actor, :read
    @subject.grant @cascader, :read

    perform_enqueued_jobs(only: [ClearAbilitiesJob]) { Ability.clear(@cascader) }

    refute_able @actor, :read, @cascader
    refute_able @cascader, :read, @subject
    refute_able @actor, :read, @subject
  end

  test "removing all abilities on a participant cleans up ancestry" do
    @cascader.grant @actor, :read
    @subject.grant @cascader, :read

    perform_enqueued_jobs(only: [ClearAbilitiesJob]) { Ability.clear(@cascader) }
  end

  test "clearing abilities on a participant in a chain revokes all related abilities" do
    top    = AnActor.create
    middle = AnActorAndSubject.create
    bottom = ASubject.create

    bottom.grant middle, :read
    middle.grant top, :read
    assert_able top, :read, bottom

    perform_enqueued_jobs(only: [ClearAbilitiesJob]) { Ability.clear(middle) }

    refute_able top, :read, middle
    refute_able middle, :read, bottom
    refute_able top, :read, bottom
  end

  test "can list the abilities of an actor" do
    @parent.grant @actor, :read
    @subject.grant @actor, :read

    subjects = @actor.abilities.map(&:subject)

    assert_includes subjects, @parent
    assert_includes subjects, @subject
  end

  test "can list the abilities of an actor, while restricting type" do
    @parent.grant @actor, :read
    @subject.grant @actor, :read

    subjects = @actor.abilities(types: [@subject.class]).map(&:subject)

    assert_includes subjects, @subject
    refute_includes subjects, @parent
  end

  test "can list the abilities of an actor with no duplicate subjects" do
    @cascader.grant @actor, :read
    @subject.grant @cascader, :read
    @subject.grant @actor, :read

    subjects = @actor.abilities(types: [@subject.class]).map(&:subject)
    assert_includes subjects, @subject
  end

  test "can list the grants of a subject" do
    @subject.grant @cascader, :read
    @subject.grant @actor, :read

    actors = Ability.grants(@subject).map(&:actor)

    assert_includes actors, @cascader
    assert_includes actors, @actor
  end

  test "can list the grants of a subject with no duplicate actors" do
    @cascader.grant @actor, :read
    @subject.grant @cascader, :read
    @subject.grant @actor, :read

    actors = Ability.grants(@subject).map(&:actor)
    assert_includes actors, @actor
  end

  test "a direct ability is > an indirect ability" do
    direct = @subject.grant(@cascader, :write)
    indirect = direct.dup.tap { |a| a.priority = :indirect }

    assert direct > indirect
  end

  test "an ability with a greater action is > one with lesser" do
    read  = @subject.grant @actor, :read
    write = @subject.grant @actor, :write
    admin = @subject.grant @actor, :admin

    assert write > read
    assert admin > read
    assert admin > write
    assert read < write
    assert read < admin
    assert write < admin
  end

  test "an ability is equivalent to itself when compared with <=>" do
    direct = @subject.grant @actor, :read
    assert_equal 0, direct <=> direct
  end

  test "destroying a subject revokes abilities on the subject" do
    top    = AnActor.create
    middle = AnActorAndSubject.create
    bottom = ASubject.create

    bottom.grant middle, :read
    middle.grant top, :read
    assert_able top, :read, bottom

    perform_enqueued_jobs(only: [ClearAbilitiesJob]) { bottom.destroy }

    assert_able top, :read, middle
    refute_able top, :read, bottom
    refute_able middle, :read, bottom
  end

  test "destroying an actor revokes abilities on the actor" do
    top    = AnActor.create
    middle = AnActorAndSubject.create
    bottom = ASubject.create

    bottom.grant middle, :read
    middle.grant top, :read
    assert_able top, :read, bottom

    perform_enqueued_jobs(only: [ClearAbilitiesJob]) { top.destroy }

    refute_able top, :read, middle
    refute_able top, :read, bottom
    assert_able middle, :read, bottom
  end

  test "destroying the middle of an indirect chain revokes related abilities" do
    top    = AnActor.create
    middle = AnActorAndSubject.create
    bottom = ASubject.create

    bottom.grant middle, :read
    middle.grant top, :read
    assert_able top, :read, bottom

    perform_enqueued_jobs(only: [ClearAbilitiesJob]) { middle.destroy }

    refute_able top, :read, middle
    refute_able middle, :read, bottom
    refute_able top, :read, bottom
  end

  test "a direct ability doesn't have a parent nor a grandparent" do
    ability = @subject.grant @actor, :read
    assert_equal 0, ability.parent_id
  end

  test "granting an ability triggers an event" do
    events = subscribe "ability.grant"

    @subject.grant @actor, :read

    assert event = events.pop, "expected an event to be instrumented"
    expected_payload = {
      action: :read,
      priority: :direct,
      ability_actor_type: @actor.ability_type,
      ability_actor_id: @actor.ability_id,
      ability_subject_type: @subject.ability_type,
      ability_subject_id: @subject.ability_id,
      grantor_id: nil,
      role_name: :read
    }
    assert_equal expected_payload, event.payload
  end

  test "revoking an ability triggers an event" do
    events = subscribe "ability.revoke"

    ability = @subject.grant @actor, :read
    @subject.revoke @actor

    assert event = events.pop, "expected an event to be instrumented"
    expected_payload = {
      action: :read,
      priority: :direct,
      ability_actor_type: @actor.ability_type,
      ability_actor_id: @actor.ability_id,
      ability_subject_type: @subject.ability_type,
      ability_subject_id: @subject.ability_id
    }
    assert_equal expected_payload, event.payload
  end

  test "event payload includes actor and subject type/id information" do
    ability = @subject.grant @actor, :read

    expected_payload = {
      action: :read,
      priority: :direct,
      ability_actor_type: @actor.ability_type,
      ability_actor_id: @actor.ability_id,
      ability_subject_type: @subject.ability_type,
      ability_subject_id: @subject.ability_id,
    }
    assert_equal expected_payload, ability.event_payload
  end

  test "grant event payload includes role_name for role" do
    events = subscribe "ability.grant"

    Ability.grant(@actor, :write, @subject, role_name: "maintain")

    assert event = events.pop, "expected an event to be instrumented"
    expected_payload = {
      action: :write,
      priority: :direct,
      ability_actor_type: @actor.ability_type,
      ability_actor_id: @actor.ability_id,
      ability_subject_type: @subject.ability_type,
      ability_subject_id: @subject.ability_id,
      grantor_id: nil,
      role_name: :maintain,
    }
    assert_equal expected_payload, event.payload
  end

  test "grant event payload includes role_name for legacy permissions" do
    events = subscribe "ability.grant"

    Ability.grant(@actor, :write, @subject)

    assert event = events.pop, "expected an event to be instrumented"
    expected_payload = {
      action: :write,
      priority: :direct,
      ability_actor_type: @actor.ability_type,
      ability_actor_id: @actor.ability_id,
      ability_subject_type: @subject.ability_type,
      ability_subject_id: @subject.ability_id,
      grantor_id: nil,
      role_name: :write,
    }
    assert_equal expected_payload, event.payload
  end

  test "grant event payload includes grantor_id" do
    grantor = create(:user)
    events = subscribe "ability.grant"
    @subject.grant @actor, :read, grantor: grantor

    assert event = events.pop, "expected an event to be instrumented"
    expected_payload = { grantor_id: grantor.id }
    assert_equal expected_payload, event.payload.slice(:grantor_id)
  end

  test "event payload does not require an AR model to function" do
    actor = Class.new do
      include Ability::Actor
      def ability_id; 10; end
      def ability_type; "NonARActor"; end
      def can_be_granted_permission_over!(subject, action); end
    end.new

    subject = Class.new do
      include Ability::Subject
      def ability_id; 20; end
      def ability_type; "NonARSubject"; end
      public :grant
    end.new

    ability = subject.grant actor, :read

    expected_payload = {
      action: :read,
      priority: :direct,
      ability_actor_type: actor.ability_type,
      ability_actor_id: actor.ability_id,
      ability_subject_type: subject.ability_type,
      ability_subject_id: subject.ability_id,
    }
    assert_equal expected_payload, ability.event_payload
  end

  context "type checking" do
    test "can with nil actor returns false" do
      refute Ability.can?(nil, :admin, @actor)
    end

    test "can with nil subject returns false" do
      refute Ability.can?(@actor, :admin, nil)
    end
  end

  context ".revoke_abilities" do
    test "destroys ability records" do
      other_actor = AnActor.create

      @subject.grant other_actor, :read
      assert_able other_actor, :read, @subject

      @subject.grant @actor, :write
      assert_able @actor, :write, @subject

      Ability.revoke_abilities(Ability.where(subject_id: @subject.id))

      refute_able other_actor, :read, @subject
      refute_able @actor, :write, @subject
    end
  end

  context ".delete_all_abilities" do
    test "deletes ability records with necessary callbacks" do
      events = subscribe "ability.revoke"
      other_actor = AnActor.create

      read_ability = @subject.grant other_actor, :read
      assert_able other_actor, :read, @subject

      write_ability = @subject.grant @actor, :write
      assert_able @actor, :write, @subject

      Ability.delete_all_abilities(Ability.where(subject_id: @subject.id, subject_type: @subject.class.name))
      job = assert_enqueued_with(job: DeleteDependentAbilitiesJob, queue: "delete_dependent_abilities")
      assert_equal [read_ability.id, write_ability.id].sort, job.arguments.first.sort

      assert read_event = events.find { |e| e.payload[:action] == :read }, "expected an event with read action to be instrumented"
      assert write_event = events.find { |e| e.payload[:action] == :write }, "expected an event with write action to be instrumented"

      expected_read_payload = {
        action: :read,
        priority: :direct,
        ability_actor_type: other_actor.ability_type,
        ability_actor_id: other_actor.ability_id,
        ability_subject_type: @subject.ability_type,
        ability_subject_id: @subject.ability_id
      }

      expected_write_payload = {
        action: :write,
        priority: :direct,
        ability_actor_type: @actor.ability_type,
        ability_actor_id: @actor.ability_id,
        ability_subject_type: @subject.ability_type,
        ability_subject_id: @subject.ability_id
      }

      assert_equal expected_read_payload, read_event.payload
      assert_equal expected_write_payload, write_event.payload

      refute_able other_actor, :read, @subject
      refute_able @actor, :write, @subject
    end

    test "raises ArgumentError if subject type is Repository" do
      actor = create :user
      @org_repo.send(:grant, actor, :read)

      assert_able actor, :read, @org_repo

      assert_raises(ArgumentError) do
        Ability.delete_all_abilities(Ability.where(subject_id: @org_repo.id))
      end

      assert_able actor, :read, @org_repo
    end

    test "raises ActiveRecord error if delete fails" do
      exception = ActiveRecord::StatementInvalid.new("delete failed")
      Ability.stubs(:delete_dependent_abilities_for).raises(exception)

      other_actor = AnActor.create

      read_ability = @subject.grant other_actor, :read
      assert_able other_actor, :read, @subject

      write_ability = @subject.grant @actor, :write
      assert_able @actor, :write, @subject

      Failbot.expects(:report).with(exception, anything).once

      assert_raises(ActiveRecord::StatementInvalid) do
        Ability.delete_all_abilities(Ability.where(subject_id: @subject.id, subject_type: @subject.class.name))
      end

      assert_able other_actor, :read, @subject
      assert_able @actor, :write, @subject
    end
  end

  context "FGP subjects" do
    context "IntegrationInstallation actor" do
      test "subject_type with Repository/* prefix returns an IntegrationInstallation::AbilityCollection" do
        repo         = create(:repository, :minimal)
        installation = make_integration_installation(repository: repo, permissions: { "metadata" => :read })

        # If the feature flag for dual writing FGP is enabled then
        # we end up with 2 of the same type of ability record.
        installation.abilities.each do |ability|
          subject = ability.subject
          assert_kind_of IntegrationInstallation::AbilityCollection, subject

          assert_equal "#{Repository::Resources::INDIVIDUAL_ABILITY_TYPE_PREFIX}/metadata", subject.ability_type
          assert_equal repo, subject.parent
        end
      end

      test "subject_type with User/repositories/* prefix returns an IntegrationInstallation::AbilityCollection" do
        user         = create(:user)
        installation = make_integration_installation(target: user, permissions: { "metadata" => :read })

        # If the feature flag for dual writing FGP is enabled then
        # we end up with 2 of the same type of ability record.
        installation.abilities.each do |ability|
          subject = ability.subject
          assert_kind_of IntegrationInstallation::AbilityCollection, subject

          assert_equal "#{Repository::Resources::ALL_ABILITY_TYPE_PREFIX}/metadata", subject.ability_type
          assert_equal installation.target, subject.parent
        end
      end

      test "subject_type with Organization/* prefix returns an IntegrationInstallation::AbilityCollection" do
        org          = create(:organization)
        installation = make_integration_installation(target: org, permissions: { "members" => :read })

        # If the feature flag for dual writing FGP is enabled then
        # we end up with 2 of the same type of ability record.
        installation.abilities.each do |ability|
          subject = ability.subject
          assert_kind_of IntegrationInstallation::AbilityCollection, subject

          assert_equal "#{Organization::Resources::ABILITY_TYPE_PREFIX}/members", subject.ability_type
          assert_equal installation.target, subject.parent
        end
      end

      test "subject_type with ProtectedBranch/* prefix returns an IntegrationInstallation::AbilityCollection" do
        repo         = create(:repository, :minimal)
        installation = make_integration_installation(repository: repo, permissions: { "metadata" => :read, "contents" => :read })

        protected_branch = create(:protected_branch, repository: repo)

        subject = protected_branch.resources.contents
        action  = :write

        Permissions::Service.grant_app_permission(actor: installation, subject: subject, action: action)

        abilities = installation.abilities.select do |record|
          record.subject_type == "#{ProtectedBranch::Resources::ABILITY_TYPE_PREFIX}/contents"
        end

        assert_equal 1, abilities.size

        ability = abilities.first
        subject = ability.subject

        assert_kind_of IntegrationInstallation::AbilityCollection, subject
        assert_equal protected_branch, subject.parent
      end
    end

    context "OauthAuthorization actor" do
      test "#subject returns the OauthAuthorization::AbilityCollection subject" do
        integration   = create(:integration, default_permissions: { "emails" => :read })
        access        = create(:oauth_access, application: integration)
        authorization = access.authorization

        # If the feature flag for dual writing FGP is enabled then
        # we end up with 2 of the same type of ability record.
        authorization.abilities.each do |_ability|
          subject = authorization.abilities.first.subject
          assert_kind_of OauthAuthorization::AbilityCollection, subject

          assert_equal authorization.user, subject.parent
        end
      end
    end
  end

  context "triage role" do
    test "requesting a triage grant on an org-owned repo creates a read ability and a triage role" do
      @org_repo.send(:grant, @triage_user, :triage)

      assert Ability.can?(@triage_user, :read, @org_repo)
      refute Ability.can?(@triage_user, :write, @org_repo)
      assert UserRole.find_by(role: Role.triage_role, actor: @triage_user, target: @org_repo).present?
    end

    test "requesting a triage grant on a user-owned repo fails" do
      user_repo = create(:repository, :minimal)
      assert_raises(ArgumentError) do
        user_repo.send(:grant, @triage_user, :triage)
      end

      refute Ability.can?(@triage_user, :read, user_repo)
      refute UserRole.find_by(role: Role.triage_role, actor: @triage_user, target: user_repo).present?
    end

    test "revoking a read grant also revokes the triage role if it exists for that user" do
      @org_repo.send(:grant, @triage_user, :triage)

      Ability.revoke(@triage_user, @org_repo)
      refute Ability.can?(@triage_user, :read, @org_repo)
      refute UserRole.find_by(role: Role.triage_role, actor: @triage_user, target: @org_repo).present?
    end

    test "requesting a write grant for a user with an existing triage role revokes the triage role" do
      @org_repo.send(:grant, @triage_user, :triage)
      refute Ability.can?(@triage_user, :write, @org_repo)
      assert UserRole.find_by(role: Role.triage_role, actor: @triage_user, target: @org_repo).present?

      @org_repo.send(:grant, @triage_user, :write)
      assert Ability.can?(@triage_user, :write, @org_repo)
      refute UserRole.find_by(role: Role.triage_role, actor: @triage_user, target: @org_repo).present?
    end

    test "changing from triage to read access revokes the triage role" do
      @org_repo.send(:grant, @triage_user, :triage)
      assert Ability.can?(@triage_user, :read, @org_repo)
      assert UserRole.find_by(role: Role.triage_role, actor: @triage_user, target: @org_repo).present?

      @org_repo.send(:grant, @triage_user, :read)
      assert Ability.can?(@triage_user, :read, @org_repo)
      refute UserRole.find_by(role: Role.triage_role, actor: @triage_user, target: @org_repo).present?
    end

    test "changing from triage to maintain revokes the triage role" do
      @org_repo.send(:grant, @triage_user, :triage)
      assert Ability.can?(@triage_user, :read, @org_repo)
      assert UserRole.find_by(role: Role.triage_role, actor: @triage_user, target: @org_repo).present?

      @org_repo.send(:grant, @triage_user, :maintain)
      assert Ability.can?(@triage_user, :write, @org_repo)
      refute UserRole.find_by(role: Role.triage_role, actor: @triage_user, target: @org_repo).present?
      assert UserRole.find_by(role: Role.maintain_role, actor: @triage_user, target: @org_repo).present?
    end

    test "changing from triage to write revokes triage role" do
      @org_repo.send(:grant, @triage_user, :triage)
      assert Ability.can?(@triage_user, :read, @org_repo)
      assert UserRole.find_by(role: Role.triage_role, actor: @triage_user, target: @org_repo).present?

      @org_repo.send(:grant, @triage_user, :write)
      assert Ability.can?(@triage_user, :write, @org_repo)
      refute UserRole.find_by(role: Role.triage_role, actor: @triage_user, target: @org_repo).present?
    end

    test "changing a team from triage to read revokes triage role" do
      triage_team = create(:team, organization: @org_on_business_plus)
      triage_team.add_member(@triage_user)

      @org_repo.send(:grant, triage_team, :triage)
      assert Ability.can?(@triage_user, :read, @org_repo)
      assert UserRole.find_by(role: Role.triage_role, actor: triage_team, target: @org_repo).present?

      @org_repo.send(:grant, triage_team, :read)
      assert Ability.can?(@triage_user, :read, @org_repo)
      refute UserRole.find_by(role: Role.triage_role, actor: triage_team, target: @org_repo).present?
    end
  end

  context "maintain role" do
    test "requesting a maintain grant on an org-owned repo creates a read ability and a maintain role" do
      @org_repo.send(:grant, @maintain_user, :maintain)

      assert Ability.can?(@maintain_user, :write, @org_repo)
      refute Ability.can?(@maintain_user, :admin, @org_repo)
      assert UserRole.find_by(role: Role.maintain_role, actor: @maintain_user, target: @org_repo).present?
    end

    test "requesting a maintain grant on a user-owned repo fails" do
      user_repo = create(:repository, :minimal)
      assert_raises(ArgumentError) do
        user_repo.send(:grant, @maintain_user, :maintain)
      end

      refute Ability.can?(@maintain_user, :write, user_repo)
      refute UserRole.find_by(role: Role.maintain_role, actor: @maintain_user, target: user_repo).present?
    end

    test "revoking a write grant also revokes the maintain role if it exists for that user" do
      @org_repo.send(:grant, @maintain_user, :maintain)

      Ability.revoke(@maintain_user, @org_repo)
      refute Ability.can?(@maintain_user, :write, @org_repo)
      refute UserRole.find_by(role: Role.maintain_role, actor: @maintain_user, target: @org_repo).present?
    end

    test "requesting an admin grant for a user with an existing maintain role revokes the maintain role" do
      @org_repo.send(:grant, @maintain_user, :maintain)
      refute Ability.can?(@maintain_user, :admin, @org_repo)
      assert UserRole.find_by(role: Role.maintain_role, actor: @maintain_user, target: @org_repo).present?

      @org_repo.send(:grant, @maintain_user, :admin)
      assert Ability.can?(@maintain_user, :admin, @org_repo)
      refute UserRole.find_by(role: Role.maintain_role, actor: @maintain_user, target: @org_repo).present?
    end

    test "changing from maintain to write access revokes the maintain role" do
      @org_repo.send(:grant, @maintain_user, :maintain)
      assert Ability.can?(@maintain_user, :write, @org_repo)
      assert UserRole.find_by(role: Role.maintain_role, actor: @maintain_user, target: @org_repo).present?

      @org_repo.send(:grant, @maintain_user, :write)
      assert Ability.can?(@maintain_user, :write, @org_repo)
      refute UserRole.find_by(role: Role.maintain_role, actor: @maintain_user, target: @org_repo).present?
    end

    test "changing from maintain to triage revokes the maintain role" do
      @org_repo.send(:grant, @maintain_user, :maintain)
      assert Ability.can?(@maintain_user, :write, @org_repo)
      assert UserRole.find_by(role: Role.maintain_role, actor: @maintain_user, target: @org_repo).present?

      @org_repo.send(:grant, @maintain_user, :triage)
      assert Ability.can?(@maintain_user, :read, @org_repo)
      refute UserRole.find_by(role: Role.maintain_role, actor: @maintain_user, target: @org_repo).present?
      assert UserRole.find_by(role: Role.triage_role, actor: @maintain_user, target: @org_repo).present?
    end

    test "changing from maintain to read revokes maintain role" do
      @org_repo.send(:grant, @maintain_user, :maintain)
      assert Ability.can?(@maintain_user, :write, @org_repo)
      assert UserRole.find_by(role: Role.maintain_role, actor: @maintain_user, target: @org_repo).present?

      @org_repo.send(:grant, @maintain_user, :read)
      assert Ability.can?(@maintain_user, :read, @org_repo)
      refute UserRole.find_by(role: Role.maintain_role, actor: @maintain_user, target: @org_repo).present?
    end

    test "changing a team from maintain to read revokes maintain role" do
      maintain_team = create(:team, organization: @org_on_business_plus)
      maintain_team.add_member(@maintain_user)

      @org_repo.send(:grant, maintain_team, :maintain)
      assert Ability.can?(@maintain_user, :write, @org_repo)
      assert UserRole.find_by(role: Role.maintain_role, actor: maintain_team, target: @org_repo).present?

      @org_repo.send(:grant, maintain_team, :read)
      assert Ability.can?(@maintain_user, :read, @org_repo)
      refute UserRole.find_by(role: Role.maintain_role, actor: maintain_team, target: @org_repo).present?
    end
  end

  context "custom roles" do
    test "can grant a custom role that belongs to your org" do
      maintain = Role.maintain_role
      custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: @org_on_business_plus.id, owner_type: "Organization", base_role_id: maintain.id)
      user = create(:user)

      @org_repo.send(:grant, user, custom_role.name)
      assert Ability.can?(user, :write, @org_repo)
      assert UserRole.find_by(role: custom_role, actor: user, target: @org_repo).present?
    end
  end

  context "stats" do
    test "timing is recorded as a distribution for #can? calls" do
      Ability.can?(@actor, :admin, @org_repo)
      assert_dogstats_distribution(1, "ability.can.dist.time")
    end

    test "timing is NOT recorded as a distribution for #can? calls that involve no work" do
      Ability.can?(@actor, :admin, @actor)
      Ability.can?(nil, :admin, @actor)
      Ability.can?(@actor, :admin, nil)

      assert_dogstats_distribution(0, "ability.can.dist.time")
    end
  end
end
