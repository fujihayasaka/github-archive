# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/ability_models"

class AbilitySubjectTest < GitHub::TestCase
  test "check membership" do
    read    = AnActor.create
    write   = AnActor.create
    admin   = AnActor.create
    subject = ASubject.create

    subject.grant read, :read
    subject.grant write, :write
    subject.grant admin, :admin

    [read, write, admin].each do |actor|
      assert_able actor, :read, subject
    end
  end

  test "bulk method grants ability to multiple actors" do
    actor1  = AnActor.create
    actor2  = AnActor.create
    actor3  = AnActor.create
    subject = ASubject.create

    [actor1, actor2, actor3].each do |actor|
      refute_able actor, :read, subject
    end

    subject.bulk_grant [actor1, actor2, actor3], :read

    [actor1, actor2, actor3].each do |actor|
      assert_able actor, :read, subject
    end
  end

  test "list members via grants" do
    actor = AnActor.create
    subject = ASubject.create

    subject.grant actor, :read
    assert_equal [actor], Ability.grants(subject).map(&:actor)
  end

  test "list indirect members via grants" do
    actor = AnActor.create
    subject = ASubject.create
    connector = AnActorAndSubject.create

    subject.grant connector, :read
    connector.grant actor, :read

    assert_same_elements [actor, connector], Ability.grants(subject).map(&:actor)
    indirect = Ability.grants(subject).detect { |g| g.actor == actor }
    assert indirect.created_at, "includes a created_at timestamp"
    assert indirect.updated_at, "includes an updated_at timestamp"
  end

  test "list actor_ids of a given type" do
    reader    = AnActor.create
    parent    = AnActor.create
    connector = AnActorAndSubject.create
    subject   = ASubject.create

    subject.grant reader, :read
    subject.grant connector, :read
    connector.grant parent, :read

    assert_equal [connector.id], subject.actor_ids(type: AnActorAndSubject)
    assert_equal [reader.id, parent.id], subject.actor_ids(type: AnActor)
  end

  test "list actor_ids with a minimum action" do
    reader  = AnActor.create
    writer  = AnActor.create
    admin   = AnActor.create
    subject = ASubject.create

    subject.grant reader, :read
    subject.grant writer, :write
    subject.grant admin, :admin

    assert_equal [reader.id, writer.id, admin.id], subject.actor_ids(type: AnActor, min_action: :read)
    assert_equal [writer.id, admin.id], subject.actor_ids(type: AnActor, min_action: :write)
    assert_equal [admin.id], subject.actor_ids(type: AnActor, min_action: :admin)
  end

  test "list actor_ids with a minimum action works for indirect abilities too" do
    read_connector  = AnActorAndSubject.create
    write_connector = AnActorAndSubject.create
    reader          = AnActor.create
    writer          = AnActor.create
    subject         = ASubject.create
    subject.grant read_connector, :read
    subject.grant write_connector, :write
    read_connector.grant reader, :read
    write_connector.grant writer, :read

    assert_equal [reader.id, writer.id], subject.actor_ids(type: AnActor, min_action: :read)
    assert_equal [writer.id], subject.actor_ids(type: AnActor, min_action: :write)
    assert_equal [], subject.actor_ids(type: AnActor, min_action: :admin)
  end

  test "list actor_ids returns unique actor ids" do
    actor = AnActor.create
    connector = AnActorAndSubject.create
    subject = ASubject.create

    subject.grant actor, :read
    subject.grant connector, :read
    connector.grant actor, :read

    assert_equal [actor.id], subject.actor_ids(type: AnActor)
  end

  test "list actor_ids with a filter list of ids to return" do
    read_connector  = AnActorAndSubject.create
    write_connector = AnActorAndSubject.create
    reader          = AnActor.create
    writer          = AnActor.create
    subject         = ASubject.create
    subject.grant read_connector, :read
    subject.grant write_connector, :write
    read_connector.grant reader, :read
    write_connector.grant writer, :read

    assert_equal [reader.id], subject.actor_ids(type: AnActor, min_action: :read, actor_ids_filter: [reader.id])
    assert_equal [], subject.actor_ids(type: AnActor, min_action: :write, actor_ids_filter: [reader.id])
  end

  test "list actor_ids with a transferred repository within an org includes org admin" do
    @actor    = create(:user)

    @org            = create(:organization)
    @org_owned_repo = create(:repository, owner: @org, from_example: :simple)
    @org_admin1     = @org.admins.first
    @org.allow_private_repository_forking(actor: @org_admin1, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)

    @forking_user            = create(:user)

    # public org-owned repo forked by a user
    forked = create(:fork_repository, forker: @forking_user, fork_repo: @org_owned_repo)
    # fork org-owned repo
    @org_owned_repo.update_attribute :private, true
    readers = create :team, organization: @org, permission: "pull"
    readers.add_repository @org_owned_repo, :pull
    readers.add_member @forking_user
    forked, status = @org_owned_repo.fork forker: @forking_user

    # parent repo's org still has administrative privileges on fork
    assert_equal @org.id, forked.owning_organization_id

    # transfer ownership of parent repo
    new_org = create(:organization, plan: "silver")
    new_org_admin = new_org.admins.first
    new_org.add_admin(@forking_user)
    @org_owned_repo.transfer_ownership_to(new_org, actor: @actor)

    assert_equal [@org_admin1.id], forked.actor_ids(type: User, min_action: :admin)
    assert_equal [], forked.actor_ids(type: Team, min_action: :read)
  end

  test "actor_ids requries a type argument" do
    assert_raises ArgumentError do
      ASubject.create.actor_ids
    end
  end

  test "actor_ids requires a valid min_action" do
    assert_raises(ArgumentError) do
      ASubject.create.actor_ids(type: AnActor, min_action: :invalid)
    end
  end

  test "doesn't complain about revoking nonexistent grants" do
    actor   = AnActor.create
    subject = ASubject.create

    subject.revoke actor
  end

  test "dependent_added cascades admin permission to the given dependent" do
    subject = ASubject.create
    connector = AnActorAndSubject.create # no dependents, doing it manually
    actor = AnActor.create

    connector.grant actor, :admin
    connector.dependent_added subject

    assert_able actor, :admin, subject
  end

  test "dependent_added can be called repeatedly without adverse effect" do
    subject = ASubject.create
    connector = AnActorAndSubject.create # no dependents, doing it manually
    actor = AnActor.create

    connector.grant actor, :admin

    connector.dependent_added subject
    connector.dependent_added subject

    assert_able actor, :admin, subject
  end

  context "refactor_subject_actor_ids_enabled?" do
    test "returns false if the subject is a repository" do
      GitHub.flipper[:refactor_subject_actor_ids].enable
      org = create(:organization)
      org_owned_repo = create(:repository, owner: org)
      refute org_owned_repo.refactor_subject_actor_ids_enabled?
    end

    test "returns true if the subject is an org" do
      GitHub.flipper[:refactor_subject_actor_ids].enable
      org = create(:organization)
      assert org.refactor_subject_actor_ids_enabled?
    end

    test "returns false if the FF is off" do
      GitHub.flipper[:refactor_subject_actor_ids].disable
      org = create(:organization)
      org_owned_repo = create(:repository, owner: org)
      refute org_owned_repo.refactor_subject_actor_ids_enabled?
    end

    test "returns false if the subject is a team" do
      GitHub.flipper[:refactor_subject_actor_ids].enable
      org = create(:organization)
      team = create(:team, organization: org)
      refute team.refactor_subject_actor_ids_enabled?
    end
  end

  context "experiment_actor_ids" do
    test "list actor_ids of a given type" do
      reader    = AnActor.create
      parent    = AnActor.create
      connector = AnActorAndSubject.create
      subject   = ASubject.create

      subject.grant reader, :read
      subject.grant connector, :read
      connector.grant parent, :read

      assert_equal [connector.id], subject.experiment_actor_ids(type: AnActorAndSubject)
      assert_equal [reader.id, parent.id], subject.experiment_actor_ids(type: AnActor)
    end

    test "list actor_ids with a minimum action" do
      reader  = AnActor.create
      writer  = AnActor.create
      admin   = AnActor.create
      subject = ASubject.create

      subject.grant reader, :read
      subject.grant writer, :write
      subject.grant admin, :admin

      assert_equal [reader.id, writer.id, admin.id], subject.experiment_actor_ids(type: AnActor, min_action: :read)
      assert_equal [writer.id, admin.id], subject.experiment_actor_ids(type: AnActor, min_action: :write)
      assert_equal [admin.id], subject.experiment_actor_ids(type: AnActor, min_action: :admin)
    end

    test "list actor_ids with a minimum action works for indirect abilities too" do
      read_connector  = AnActorAndSubject.create
      write_connector = AnActorAndSubject.create
      reader          = AnActor.create
      writer          = AnActor.create
      subject         = ASubject.create
      subject.grant read_connector, :read
      subject.grant write_connector, :write
      read_connector.grant reader, :read
      write_connector.grant writer, :read

      assert_equal [reader.id, writer.id], subject.experiment_actor_ids(type: AnActor, min_action: :read)
      assert_equal [writer.id], subject.experiment_actor_ids(type: AnActor, min_action: :write)
      assert_equal [], subject.experiment_actor_ids(type: AnActor, min_action: :admin)
    end

    test "list actor_ids returns unique actor ids" do
      actor = AnActor.create
      connector = AnActorAndSubject.create
      subject = ASubject.create

      subject.grant actor, :read
      subject.grant connector, :read
      connector.grant actor, :read

      assert_equal [actor.id], subject.experiment_actor_ids(type: AnActor)
    end

    test "list actor_ids with a filter list of ids to return" do
      read_connector  = AnActorAndSubject.create
      write_connector = AnActorAndSubject.create
      reader          = AnActor.create
      writer          = AnActor.create
      subject         = ASubject.create
      subject.grant read_connector, :read
      subject.grant write_connector, :write
      read_connector.grant reader, :read
      write_connector.grant writer, :read

      assert_equal [reader.id], subject.experiment_actor_ids(type: AnActor, min_action: :read, actor_ids_filter: [reader.id])
      assert_equal [], subject.experiment_actor_ids(type: AnActor, min_action: :write, actor_ids_filter: [reader.id])
    end

    test "list actor_ids with a transferred repository within an org includes org admin" do
      @actor    = create(:user)

      @org            = create(:organization)
      @org_owned_repo = create(:repository, owner: @org, from_example: :simple)
      @org_admin1     = @org.admins.first
      @org.allow_private_repository_forking(actor: @org_admin1, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)

      @forking_user            = create(:user)

      # public org-owned repo forked by a user
      forked = create(:fork_repository, forker: @forking_user, fork_repo: @org_owned_repo)
      # fork org-owned repo
      @org_owned_repo.update_attribute :private, true
      readers = create :team, organization: @org, permission: "pull"
      readers.add_repository @org_owned_repo, :pull
      readers.add_member @forking_user
      forked, status = @org_owned_repo.fork forker: @forking_user

      # parent repo's org still has administrative privileges on fork
      assert_equal @org.id, forked.owning_organization_id

      # transfer ownership of parent repo
      new_org = create(:organization, plan: "silver")
      new_org_admin = new_org.admins.first
      new_org.add_admin(@forking_user)
      @org_owned_repo.transfer_ownership_to(new_org, actor: @actor)

      assert_equal [@org_admin1.id], forked.experiment_actor_ids(type: User, min_action: :admin)
      assert_equal [], forked.experiment_actor_ids(type: Team, min_action: :read)
    end

    test "experiment_actor_ids requries a type argument" do
      assert_raises ArgumentError do
        ASubject.create.experiment_actor_ids
      end
    end

    test "experiment_actor_ids requires a valid min_action" do
      assert_raises(ArgumentError) do
        ASubject.create.experiment_actor_ids(type: AnActor, min_action: :invalid)
      end
    end
  end
end
