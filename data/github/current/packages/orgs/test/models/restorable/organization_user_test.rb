# typed: true
# frozen_string_literal: true

require "test_helper"

class RestorableOrganizationUserTest < GitHub::TestCase
  include AuditLogHelpers
  include GitHub::LoggerHelper

  fixtures do
    @member = create(:user)
    @org = create(:organization)
    @org.add_member(@member)
    @repo = create(:repository, :minimal, owner: @org)
    @team = create(:team, organization: @org)
    @team.add_member(@member)
    @member.star(@repo)
    @issue = create(:issue, repository: @repo, user: @member)
    @issue.assignees = [@member]
    @issue.save
  end

  def build_restorable_organization_user
    Restorable::OrganizationUser.create({
      restorable: Restorable.create,
      organization: @org,
      user: @member,
    })
  end

  test ".start creates parent Restorable and Restorable::OrganizationUser models" do
    restorable_organization_user = Restorable::OrganizationUser.start(@org, @member)

    assert_predicate restorable_organization_user, :persisted?
    assert_predicate restorable_organization_user.restorable, :persisted?
  end

  test ".start returns NullOrganizationUser if start save fails" do
    Restorable::OrganizationUser.any_instance.expects(:save).returns(false)

    restorable_organization_user = Restorable::OrganizationUser.start(@org, @member)

    assert_instance_of Restorable::NullOrganizationUser, restorable_organization_user
  end

  test ".continue returns the most recent Restorable::OrganizationUser record" do
    restorable_organization_user_first = Restorable::OrganizationUser.start(@org, @member)
    restorable_organization_user_second = Restorable::OrganizationUser.start(@org, @member)
    restorable_organization_user_continue = Restorable::OrganizationUser.continue(@org, @member)

    assert_equal restorable_organization_user_second, restorable_organization_user_continue
  end

  test ".restorable returns the most recent Restorable::OrganizationUser record" do
    restorable_organization_user_first = Restorable::OrganizationUser.start(@org, @member)
    restorable_organization_user_second = Restorable::OrganizationUser.start(@org, @member)
    Restorable::OrganizationUser.any_instance.expects(:restorable?).returns(true)
    restorable_organization_user_restorable = Restorable::OrganizationUser.restorable(@org, @member)

    assert_equal restorable_organization_user_second, restorable_organization_user_restorable
  end

  test "#save_memberships creates Restorable::Membership models" do
    restorable_organization_user = build_restorable_organization_user
    memberships = Ability.where(actor_id: @member.id)

    assert_difference("Restorable::Membership.count", 2) do
      restorable_organization_user.save_memberships(memberships)
    end
  end

  test "#save_memberships saves the correct action to the db" do
    restorable_organization_user = build_restorable_organization_user
    org2 = create(:organization)
    org3 = create(:organization)
    org4 = create(:organization)
    org2.add_member(@member, action: :read)
    org3.add_member(@member, action: :write)
    org4.add_member(@member, action: :admin)

    memberships = Ability.where(actor_id: @member.id)
    restorable_organization_user.save_memberships(memberships)

    assert_equal 5, Restorable::Membership.count

    membership_tuples = memberships.map do |m|
      [m.action, m.subject_id, m.subject_type]
    end

    Restorable::Membership.all.each do |rom|
      assert_includes membership_tuples, [rom.action, rom.subject_id, rom.subject_type]
    end
  end

  test "#save_repositories creates Restorable::Repository models" do
    restorable_organization_user = build_restorable_organization_user
    deleted_repositories = [create(:deleted_repository), create(:deleted_repository)]

    assert_difference("Restorable::Repository.count", 2) do
      restorable_organization_user.save_repositories(deleted_repositories)
    end
  end

  test "#save_repository_stars creates Restorable::Star models" do
    restorable_organization_user = build_restorable_organization_user
    repo_ids = [@repo.id]
    starred_repos = @member.starred_repositories.where(id: repo_ids)

    assert_difference("Restorable::RepositoryStar.count", 1) do
      restorable_organization_user.save_repository_stars(starred_repos)
    end
  end

  test "#save_issue_assignments creates Restorable::IssueAssignment model" do
    restorable_organization_user = build_restorable_organization_user
    repo_ids = [@repo.id]
    issues = Issue.where(repository_id: repo_ids).assigned_to(@member).includes(:assignments)

    assert_difference("Restorable::IssueAssignment.count", 1) do
      restorable_organization_user.save_issue_assignments(issues)
    end
  end

  test "#save_custom_email_routings creates Restorable::CustomEmailRouting model" do
    restorable_organization_user = build_restorable_organization_user
    custom_email = "user@org.com"
    assert_difference "Restorable::CustomEmailRouting.count", 1 do
      restorable_organization_user.save_custom_email_routings(custom_email)
    end
    restorable = Restorable::CustomEmailRouting.first
    assert_equal custom_email, restorable.email
    assert_equal @org.id, restorable.organization_id
  end

  test "#save_watched_repositories creates Restorable::WatchedRepository model" do
    restorable_organization_user = build_restorable_organization_user
    @repo.extend(WatchedRepositories::SubscriptionDetails)
    @repo.ignored = true
    repo2 = create(:repository, :minimal, owner: @org)
    repo2.extend(WatchedRepositories::SubscriptionDetails)
    repo2.ignored = false

    assert_difference("Restorable::WatchedRepository.count", 2) do
      restorable_organization_user.save_watched_repositories([@repo, repo2])
    end

    restorable1 = Restorable::WatchedRepository.where(repository_id: @repo.id).first
    restorable2 = Restorable::WatchedRepository.where(repository_id: repo2.id).first

    assert_equal restorable1.ignored?, true
    assert_equal restorable2.ignored?, false
  end

  test "#restorable? and save_<plural_model_name>_complete methods" do
    restorable = build_restorable_organization_user
    refute_predicate restorable, :restorable?
    restorable.save_memberships_complete
    refute_predicate restorable, :restorable?
    restorable.save_issue_assignments_complete
    refute_predicate restorable, :restorable?
    restorable.save_watched_repositories_complete
    refute_predicate restorable, :restorable?
    restorable.save_repository_stars_complete
    refute_predicate restorable, :restorable?
    restorable.save_repositories_complete
    refute_predicate restorable, :restorable?
    restorable.save_custom_email_routings_complete
    assert_predicate restorable, :restorable?
  end

  test "#restore only restores if restorable" do
    restorable_organization_user = build_restorable_organization_user
    restorable_organization_user.expects(:restore_memberships).never
    restorable_organization_user.restore(actor: create(:user))
  end

  test "job_status returns the JobStatus if found nil otherwise" do
    restorable_organization_user = build_restorable_organization_user
    assert_nil restorable_organization_user.job_status
    job = JobStatus.create(id: "resorable_#{restorable_organization_user.id}")
    assert job, restorable_organization_user.job_status
  end

  test ".restore sends org.restore_member to audit log" do
    events = subscribe "org.restore_member"

    actor = create(:user)
    org = create(:organization)
    user = create(:user)
    restorable = Restorable.create
    team = create :team, organization: org
    team2 = create :team, organization: org

    restorable.memberships.create({
      subject_type: "Organization",
      subject_id: org.id,
      action: :read,
    })
    restorable.memberships.create({
      subject_type: "Team",
      subject_id: team.id,
      action: :read,
    })
    restorable.memberships.create({
      subject_type: "Team",
      subject_id: team2.id,
      action: :read,
    })

    restorable_organization_user = Restorable::OrganizationUser.create({
      restorable: restorable,
      organization: org,
      user: user,
    })

    restorable_organization_user.save_memberships_complete
    restorable_organization_user.save_issue_assignments_complete
    restorable_organization_user.save_repositories_complete
    restorable_organization_user.save_watched_repositories_complete
    restorable_organization_user.save_repository_stars_complete
    restorable_organization_user.save_custom_email_routings_complete

    with_es_refresh do
      restorable_organization_user.restore(actor: actor)
    end

    expected_org_memberships = [
      { org: org.login, org_id: org.id },
      { team: team.to_s, team_id: team.id },
      { team: team2.to_s, team_id: team2.id },
    ]

    expected_payload = {
      restored_memberships: expected_org_memberships,
      restored_memberships_count: 3,
      restored_repos_count: 0,
      restored_issue_assignments_count: 0,
      restored_repo_watches_count: 0,
      restored_repo_stars_count: 0,
      restored_custom_email_routings_count: 0,
      user: user.login,
      user_id: user.id,
      org: org.login,
      org_id: org.id,
      actor: actor.login,
      actor_id: actor.id,
    }

    assert event = events.pop, "expected an org.restore_member event"
    assert_equal expected_payload, event.payload
  end

  test "logs information when save_restorable_complete is called and the restorable can't be saved" do
    restorable_organization_user = build_restorable_organization_user
    now = Time.now.utc

    Restorable.any_instance.expects(:saved).returns(false)
    Restorable.any_instance.expects(:saved?).returns(false)

    assert_logged \
      "code.namespace": "Restorable::OrganizationUser",
      "code.function": "save_restorable_complete",
      "gh.org.id": @org.id,
      "gh.thisuser": @member.id,
      timestamp: now.iso8601 do
      Timecop.freeze(now) do
        restorable_organization_user.save_memberships_complete
      end
    end
  end
end
