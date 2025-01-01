# typed: false
# frozen_string_literal: true

require "test_helper"
require "test_helpers/pull_requests"

class RepositoryTransferTest < GitHub::TestCase
  include HydroTestHelpers
  include BackgroundDeletesTestHelpers

  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?

    @source   = create :user, login: "source"
    @target   = create :user, login: "target"
    @stranger = create :user, login: "stranger"
    @repo     = create(:repository, owner: @source)
    @business = GitHub.global_business || create(:business, seats: 5)
  end

  setup do
    @orgs_admin = create(:user)
    @org_one = create(:organization, admin: @orgs_admin)
    @org_two = create(:organization, admin: @orgs_admin)

    @org_repo = create(:repository, owner: @org_one)
  end

  def build_transfer(&block)
    RepositoryTransfer.new do |t|
      t.requester       = @source
      t.repository      = @repo
      t.target          = @target
      t.new_name        = @new_name

      block.call t if block
    end
  end

  def create_transfer(&block)
    build_transfer(&block).tap { |t| t.save! }
  end

  test "stores a repository and target" do
    xfer = build_transfer
    assert xfer.requested?

    xfer.save!
    xfer.reload

    assert_equal @source, xfer.requester
    assert_equal @repo,   xfer.repository
    assert_equal @target, xfer.target
    assert_equal @source, xfer.source, "exposes repository.owner too"
  end

  context "validations" do
    context "accepting outside collaborators" do
      context "when organization allows inviting outside collaborators" do
        test "allows the repository transfer" do
          non_org_member = create(:user, login: "non-org-member")
          org = create(:organization, plan: "business")
          org.update_column(:seats, 10)

          assert_predicate org, :members_can_invite_outside_collaborators?

          repo = create :private_repository
          repo.add_member(non_org_member)
          org.add_member(repo.owner)

          xfer = RepositoryTransfer.new do |t|
            t.requester = repo.owner
            t.repository = repo
            t.target = org
          end

          assert_predicate xfer, :valid?
        end
      end

      context "when organization disallows inviting outside collaborators" do
        test "disallows the repository transfer" do
          non_org_member = create(:user, login: "non-org-member")
          org_admin = create(:user)
          org = create :organization, plan: GitHub::Plan.business_plus
          org.add_admin(org_admin)
          org.disallow_members_can_invite_outside_collaborators(actor: org_admin, force: true)

          refute_predicate org, :members_can_invite_outside_collaborators?

          org.update_column(:seats, 10)

          repo = create :private_repository
          3.times do |i|
            repo.add_member(create(:user, login: "non-org-member-#{i}"))
          end

          xfer = RepositoryTransfer.new do |t|
            t.requester = repo.owner
            t.repository = repo
            t.target = org
          end

          expected_error_msg = "This repository has collaborators not permitted by #{org.login} organization. "\
            "To transfer the repository you will need to remove these collaborators, "\
            "or enable \"Allow repository administrators to invite outside collaborators\" in the #{org.login} organization's settings."

          refute_predicate xfer, :valid?
          assert xfer.errors.full_messages.include?(expected_error_msg)
        end
      end

      context "custom properties" do
        test "skips if owner is not an org" do
          xfer = RepositoryTransfer.new do |t|
            t.requester = @source
            t.repository = @repo
            t.target = @target
            t.custom_properties = { "unknown" => "invalid value" }
          end

          assert_predicate xfer, :valid?
        end

        test "fails if properties schema is invalid" do
          xfer = RepositoryTransfer.new do |t|
            t.requester = @orgs_admin
            t.repository = @org_repo
            t.target = @org_two
            t.custom_properties = { "unknown" => "value" }
          end

          refute_predicate xfer, :valid?
          assert_equal ["Unexpected property 'unknown'"], xfer.errors.full_messages
        end

        test "fails if properties values are invalid" do
          create :custom_property_definition, source: @org_two, property_name: "env"

          xfer = RepositoryTransfer.new do |t|
            t.requester = @orgs_admin
            t.repository = @org_repo
            t.target = @org_two
            t.custom_properties = { "env" => "invalid\"value" }
          end

          refute_predicate xfer, :valid?
          assert_equal ["Property 'env' value has invalid characters: \""], xfer.errors.full_messages
        end

        test "fails to create a repo if user does not have permissions to set properties" do
          user = create(:user)
          @org_one.add_member(user)

          xfer = RepositoryTransfer.new do |t|
            t.requester = user
            t.repository = @org_repo
            t.target = @org_two
            t.custom_properties = { "env" => "value" }
          end

          refute_predicate xfer, :valid?
          assert xfer.errors.full_messages.include? "User does not have permission to set custom properties"
        end
      end
    end

    test "repository must be transferrable" do
      @repo.stubs(:can_transfer_ownership?).returns false

      xfer = build_transfer

      refute_predicate xfer, :valid?
      refute_empty xfer.errors[:repository]
    end

    test "internal repository can transfer to another org in the enterprise" do
      admin      = create(:user)
      org        = create(:organization, plan: "business", business: @business, admin: admin)
      target_org = create(:organization, plan: "business", business: @business, admin: admin)

      repo = create(:internal_repository, owner: org)

      xfer = RepositoryTransfer.new do |t|
        t.requester = admin
        t.repository = repo
        t.target = target_org
      end

      assert_predicate xfer, :valid?
      assert_empty xfer.errors[:repository]
    end

    test "internal repository can not transfer to another org outside the enterprise" do
      admin      = create(:user)
      org        = create(:organization, plan: "business", business: @business, admin: admin)
      target_org = create(:organization, plan: "business", admin: admin)

      repo = create(:internal_repository, owner: org)

      xfer = RepositoryTransfer.new do |t|
        t.requester = admin
        t.repository = repo
        t.target = target_org
      end

      refute_predicate xfer, :valid?
      assert_equal ["Internal repositories can only be transferred to an organization in the enterprise"], xfer.errors.full_messages
    end

    test "internal repository can not transfer to user account" do
      admin      = create(:user)
      org        = create(:organization, plan: "business", business: @business, admin: admin)

      repo = create(:internal_repository, owner: org)

      xfer = RepositoryTransfer.new do |t|
        t.requester = admin
        t.repository = repo
        t.target = admin
      end

      refute_predicate xfer, :valid?
      assert_equal ["Internal repositories can only be transferred to an organization in the enterprise"], xfer.errors.full_messages
    end

    test "requester must admin the repository" do
      xfer = build_transfer do |t|
        t.requester = @stranger
      end

      refute_predicate xfer, :valid?
      assert_equal ["#{@stranger} can't administer this repository"], xfer.errors.full_messages
    end

    test "requester cannot be a Bot" do
      bot = create(:integration).bot
      xfer = build_transfer do |t|
        t.requester = bot
      end

      refute_predicate xfer, :valid?
      assert_equal ["#{bot} can't administer this repository"], xfer.errors.full_messages
    end

    test "target cannot be a Bot" do
      bot = create(:integration).bot
      xfer = build_transfer do |t|
        t.target = bot
      end

      refute_predicate xfer, :valid?
      assert_equal ["#{bot} cannot own any repositories"], xfer.errors.full_messages
    end

    test "requester can be an IntegrationInstallation with administration write permissions" do
      installation = make_integration_installation(repository: @repo, permissions: { "administration" => :write })

      xfer = build_transfer do |t|
        t.requester = installation.bot
      end

      assert_predicate xfer, :valid?
    end

    test "responder must admin the target" do
      xfer = build_transfer do |t|
        # shortcut instead of going through the workflow
        t.state = :responded
        t.responder = @stranger
      end

      refute_predicate xfer, :valid?
      refute_empty xfer.errors
    end

    unless GitHub.enterprise?
      test "repo owner must not be spammy" do
        @source.mark_as_spammy(reason: "bad", actor: @target)
        assert_predicate @source, :spammy, "should be spammy"

        xfer = build_transfer do |t|
          t.requester = @source
        end

        refute_predicate xfer, :valid?
        assert_equal ["Repository transfers not available for this account"], xfer.errors.full_messages
      end
    end

    test "repo must not be locked for migration" do
      @repo.lock_for_migration

      xfer = build_transfer

      refute_predicate xfer, :valid?
      assert_equal ["Repository is locked for migration"], xfer.errors.full_messages
    end

    test "target owner must exist" do
      xfer = build_transfer do |t|
        t.target = nil
        t.requested_target = "doesnotexist"
      end

      refute_predicate xfer, :valid?
      assert_equal ["Cannot find new owner 'doesnotexist'"], xfer.errors.full_messages
    end

    context "with a private repository" do
      test "org target must have sufficient collaborator seats" do
        org = create(:organization, plan: "business")
        org.update_column(:seats, 1)

        repo = create :private_repository
        repo.add_member(create(:user))
        org.add_member(repo.owner)

        xfer = RepositoryTransfer.new do |t|
          t.requester = repo.owner
          t.repository = repo
          t.target = org
        end

        if GitHub.enterprise?
          assert_predicate xfer, :valid?
        else
          refute_predicate xfer, :valid?
          assert_equal ["#{org} has insufficient collaborator seats."], xfer.errors[:base]
        end
      end

      unless GitHub.single_business_environment?
        test "skips seat check when delegated to business and transfer is to the same business" do
          admin = create(:user)
          business = create :business, seats: 5

          org = create(:organization, plan: "business", business: business)
          org.add_admin(admin)

          repo = create(:private_repository, owner: org)

          target_org = create(:organization, plan: "business", business: business)
          target_org.add_admin(admin)

          xfer = RepositoryTransfer.new do |t|
            t.requester = admin
            t.repository = repo
            t.target = target_org
          end

          target_org.expects(:available_invitable_seats).never
          assert_predicate xfer, :valid?
        end
      end

      test "skips seat checks when org target is on a free plan" do
        org = create(:organization, plan: "free")
        org.update_column(:seats, 1)

        repo = create :private_repository
        repo.add_member(create(:user))
        org.add_member(repo.owner)

        xfer = RepositoryTransfer.new do |t|
          t.requester = repo.owner
          t.repository = repo
          t.target = org
        end

        assert_predicate xfer, :valid?
      end

      test "skips seat checks when org target is on a free with addons plan" do
        org = create(:organization, plan: "free_with_addons")
        org.update_column(:seats, 1)

        repo = create :private_repository
        repo.add_member(create(:user))
        org.add_member(repo.owner)

        xfer = RepositoryTransfer.new do |t|
          t.requester = repo.owner
          t.repository = repo
          t.target = org
        end

        assert_predicate xfer, :valid?
      end
    end

    test "request away from an organization, must be to yourself" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      org.add_admin @stranger
      assert repo.adminable_by?(@stranger)

      xfer = build_transfer do |t|
        t.target = @target
        t.requester = @stranger
        t.repository = repo
      end

      refute_predicate xfer, :valid?
      assert_equal ["You can only transfer a repository from an organization to " +
        "yourself at this time"], xfer.errors[:base]
    end

    test "target must be a different owner than current" do
      xfer = build_transfer do |t|
        t.requester = @source
        t.target = @source
      end

      refute_predicate xfer, :valid?
      assert_equal ["Repositories cannot be transferred to the original owner"], xfer.errors.full_messages
    end

    test "requester must be org admin if repo deletion is disabled on organization" do
      owner = create(:user, plan: "micro")
      member = create(:user)

      org = create(:organization, admin: owner, plan: "free")
      org.disallow_members_can_delete_repositories(actor: owner)
      org.add_member(member)

      private_repo = create(:repository, owner: org)
      private_repo.add_member(member, action: :admin)

      xfer = build_transfer do |t|
        t.target = member
        t.requester = member
        t.repository = private_repo
      end

      refute_predicate xfer, :valid?
      assert_equal ["Organization members cannot transfer repositories"], xfer.errors.full_messages
    end

    if GitHub.single_business_environment?
      test "requester must be a site admin if repo deletion is disabled on the global business" do
        owner = create(:user, plan: "micro")
        member = create(:user)

        GitHub.global_business.disallow_members_can_delete_repositories(force: true, actor: owner)
        org = create(:organization, admin: owner, plan: "free")
        org.add_member(member)

        private_repo = create(:repository, owner: org)
        private_repo.add_member(member, action: :admin)

        xfer = build_transfer do |t|
          t.target = member
          t.requester = member
          t.repository = private_repo
        end

        refute_predicate xfer, :valid?
        assert_equal ["Users cannot transfer repositories on this appliance"], xfer.errors.full_messages
      end
    end

    test "disallow_members_can_create_repositories prevents members transferring repositories" do
      member = create(:user, plan: "micro")
      owner = create(:user)
      org = create :organization, plan: GitHub::Plan.business_plus, admins: [owner]
      org.add_member member
      org.disallow_members_can_create_repositories(actor: owner)
      repo = create :private_repository, owner: member

      xfer = build_transfer do |t|
        t.target = org
        t.requester = member
        t.repository = repo
      end

      refute_predicate xfer, :valid?
      assert_equal ["You don’t have the permission to create private repositories on #{org}"], xfer.errors.full_messages
    end

    test "disallow_members_can_create_public_repositories prevents members transferring public repositories" do
      member = create(:user, plan: "micro")
      owner = create(:user)
      org = create :organization, plan: GitHub::Plan.business_plus, admins: [owner]
      org.add_member member
      org.disallow_members_can_create_public_repositories(actor: owner)
      repo = create :repository, owner: member

      xfer = build_transfer do |t|
        t.target = org
        t.requester = member
        t.repository = repo
      end

      refute_predicate xfer, :valid?
      assert_equal ["You don’t have the permission to create public repositories on #{org}"], xfer.errors.full_messages
    end

    test "disallow_members_can_create_public_repositories does not prevent owners from transferring public repositories" do
      owner = create(:user)
      org = create :organization, plan: GitHub::Plan.business_plus, admins: [owner]
      org.disallow_members_can_create_public_repositories(actor: owner)
      repo = create :repository, owner: owner

      xfer = build_transfer do |t|
        t.target = org
        t.requester = owner
        t.repository = repo
      end

      assert_predicate xfer, :valid?
    end

    test "sets new_name before validation if not provided" do
      xfer = build_transfer do |t|
        t.target = @target
        t.requester = @source
        t.repository = @repo
      end

      assert_predicate xfer, :valid?
      assert_equal @repo.name, xfer.new_name
    end

    test "validates name length" do
      xfer = build_transfer do |t|
        t.target = @target
        t.requester = @source
        t.repository = @repo
        t.new_name = "a" * (Repository::NAME_MAX_LENGTH + 1)
      end

      refute_predicate xfer, :valid?
      assert_equal ["New name is too long (maximum is 100 characters)"], xfer.errors.full_messages
      refute_equal @repo.name, xfer.new_name
    end

    test "only fails for existing target if requester can see the existing repo" do
      name = "existing-name"
      to_transfer = create(:private_repository, name: name, owner: @source)
      existing = create(:private_repository, name: name, owner: @target)

      xfer = build_transfer do |t|
        t.target = @target
        t.requester = @source
        t.repository = to_transfer
      end

      assert_predicate xfer, :valid?

      existing.set_visibility(actor: @target, visibility: Repository::PUBLIC_VISIBILITY)
      xfer = build_transfer do |t|
        t.target = @target
        t.requester = @source
        t.repository = to_transfer
      end

      refute_predicate xfer, :valid?
      assert_equal ["#{@target}/#{name} already exists"], xfer.errors.full_messages
    end
  end

  test "sets custom properties when immediate transfer", skip_enterprise: true do
    definition = create :custom_property_definition, source: @org_two, property_name: "env"

    custom_properties = { "env" => "prod" }
    org_one_repo = create(:repository, owner: @org_one)

    perform_enqueued_jobs(only: [TransferRepositoryJob, RepositoryOrchestrationJob]) do
      RepositoryTransfer.transfer_immediately(org_one_repo, @org_two, @orgs_admin, [], custom_properties: custom_properties)
    end

    org_one_repo.reload
    assert_equal org_one_repo.owner, @org_two
    assert_equal CustomPropertyValue.for_target(org_one_repo).where(definition_id: definition.id).map { |p| [p.property_name, p.value] }, [%w[env prod]]
  end

  test "provides a request token" do
    ActionMailer::Base.deliveries.clear

    str = nil
    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      str = RepositoryTransfer.start @repo, @target, @source
    end

    refute_nil str

    token = User.verify_signed_auth_token(
      token: str,
      scope: RepositoryTransfer::SCOPE,
    )

    assert_equal @target, token.user
    assert_equal RepositoryTransfer::SCOPE, token.scope

    id = token.data["id"]
    refute_nil id

    xfer = RepositoryTransfer.find id
    assert_equal @repo, xfer.repository
    assert_equal @target, xfer.target

    assert token.expires < 2.days.from_now

    mail = ActionMailer::Base.deliveries.pop
    refute_nil mail

    assert_match "transfer", mail.subject
    assert_match @repo.nwo, mail.body.to_s
  end

  test "doesn't send a transfer request email when notify flag is false" do
    ActionMailer::Base.deliveries.clear

    RepositoryTransfer.start @repo, @target, @source, false

    assert_equal 0, ActionMailer::Base.deliveries.size
  end

  test "silently renames the repository if the destination name is taken and the requester can't see the existing target" do
    name = "existing-name"
    to_transfer = create(:private_repository, name: name, owner: @source)
    existing = create(:private_repository, name: name, owner: @target)

    token = RepositoryTransfer.start to_transfer, @target, @source
    xfer = RepositoryTransfer.last
    assert xfer
    refute_equal to_transfer.name, xfer.new_name
    perform_enqueued_jobs(only: [TransferRepositoryJob, RepositoryOrchestrationJob]) do
      xfer.finish @target
    end

    refute_equal name, to_transfer.reload.name
    assert_equal @target, to_transfer.owner
  end

  test "instruments transfer start" do
    events = subscribe "repo.transfer_start"
    expected_payload = {
      visibility: :public,
      repo: @repo.name_with_owner,
      repo_id: @repo.id,
      public_repo: @repo.public?,
      user: @source.login,
      user_id: @source.id,
      fork_source: @repo.name_with_owner,
      fork_source_id: @repo.id,
      requester: @source.login,
      requester_id: @source.id,
      target: @target.login,
      target_id: @target.id,
    }

    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      RepositoryTransfer.start @repo, @target, @source
    end

    assert event = events.pop, "a repo.transfer_start event was expected"
    assert_equal expected_payload, event.payload
  end

  test "publishes transfer request start to hydro", skip_enterprise: true do
    RepositoryTransfer.start @repo, @target, @source

    assert_hydro_published_partial({
      repository: Hydro::EntitySerializer.repository(@repo),
      target: Hydro::EntitySerializer.user(@target),
      requester: Hydro::EntitySerializer.user(@source),
      responder: nil,
      criteria: :REQUEST,
      previous_owner: Hydro::EntitySerializer.user(@source)
    }, schema: "github.v1.RepositoryTransfer")
  end

  test "publishes transfer request finish to hydro", skip_enterprise: true do
    token = RepositoryTransfer.start @repo, @target, @source
    reset_hydro
    RepositoryTransfer.from(token).finish(@target)

    @repo.reload

    assert_hydro_published_partial({
      repository: Hydro::EntitySerializer.repository(@repo),
      target: Hydro::EntitySerializer.user(@target),
      requester: Hydro::EntitySerializer.user(@source),
      responder: Hydro::EntitySerializer.user(@target),
      criteria: :REQUEST,
      previous_owner: Hydro::EntitySerializer.user(@source)
    }, schema: "github.v1.RepositoryTransfer")
  end

  test "publishes immediate transfer to hydro", skip_enterprise: true do
    target_org = create(:organization, admin: @source)
    RepositoryTransfer.transfer_immediately @repo, target_org, @source, []

    assert_hydro_published_partial({
      repository: Hydro::EntitySerializer.repository(@repo),
      target: Hydro::EntitySerializer.user(target_org),
      requester: Hydro::EntitySerializer.user(@source),
      criteria: :IMMEDIATE,
      previous_owner: Hydro::EntitySerializer.user(@source)
    }, schema: "github.v1.RepositoryTransfer")
  end

  test "performs via a response token" do
    token = RepositoryTransfer.start @repo, @target, @source
    xfer  = RepositoryTransfer.from token

    perform_enqueued_jobs(only: [TransferRepositoryJob, RepositoryOrchestrationJob]) do
      xfer.finish @target
    end

    assert_nil   RepositoryTransfer.find_by_id(xfer.id)
    assert_equal @repo, xfer.repository
    assert_equal @target, xfer.responder
    assert_equal @target, xfer.repository.reload.owner
  end

  test "doesn't respond to invalid tokens" do
    # this token actually returns a different invalid reason than the one below
    assert_nil RepositoryTransfer.from("bad-token")

    token = @target.signed_auth_token \
      data: { "id" => "0" },
      expires: 1.day.from_now,
      scope: RepositoryTransfer::SCOPE

    assert_nil RepositoryTransfer.from("#{token}If")

    Timecop.travel(5.days) do
      assert_equal :expired_token, RepositoryTransfer.from(token)
    end
  end

  test "doesn't respond to tokens with bad xfer IDs" do
    token = @target.signed_auth_token \
      data: { "id" => "0" },
      expires: 1.day.from_now,
      scope: RepositoryTransfer::SCOPE

    assert_nil RepositoryTransfer.from token
  end

  test "doesn't allow multiple transfers for the same repo" do
    xfer = create_transfer
    req  = build_transfer
    res  = build_transfer { |t| t.state = :responded }

    refute req.valid?
    refute res.valid?
  end

  test "create transfer with differing org owners" do
    owner    = create(:user)
    source   = create(:organization, admin: owner)
    target   = create(:organization)
    repo     = create(:repository, owner: source)
    target.add_admin(owner)

    xfer = build_transfer do |t|
      t.requester = owner
      t.repository = repo
      t.target = target
    end

    assert xfer.requested?
  end

  test "performs transfer for a new org owner" do
    user     = create(:user)
    source   = create(:organization, admin: user)
    target   = create(:organization, admin: user)
    repo     = create(:repository, owner: source)

    token = RepositoryTransfer.start repo, target, user
    xfer  = RepositoryTransfer.from token

    perform_enqueued_jobs(only: [TransferRepositoryJob, RepositoryOrchestrationJob]) do
      xfer.finish target
    end

    assert_nil   RepositoryTransfer.find_by_id(xfer.id)
    assert_equal repo, xfer.repository
    assert_equal target, xfer.responder
    assert_equal target, xfer.repository.reload.owner
  end

  test "is deleted with repository" do
    transfer = create_transfer
    other_repository = create :repository, owner: @source
    other_transfer = create_transfer do |t|
      t.repository = other_repository
    end

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = @repo
      config.expect_destroyed = [transfer]
      config.expect_not_destroyed = [other_transfer]
    end
  end
end

class TransferringARepositoryTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers
  include GitHub::PullRequestTestHelpers
  include HydroTestHelpers
  include HydroMessageJobTestHelpers

  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?

    @user = create(:user, plan: "large")
    GitHub.newsies.get_and_update_settings(@user) do |settings|
      settings.auto_subscribe = true
    end
    perform_enqueued_jobs(only: [Newsies::AutoSubscribeUsersToRepositoryJob]) do
      @repo = create(:repository, :full_creation, owner: @user, from_example: :simple)
    end
    @private_repo = create(:private_repository, owner: @user, name: "private-user-repo", from_example: :simple)
    @org  = create(:business_plus_organization, admin: @user)
    @org.allow_private_repository_forking(actor: @user)

    @user2 = create(:user)
    @repo2 = create(:repository, owner: @user2, name: @repo.name)
    @user3 = create(:user)
    @user4 = create(:user)
    @user5 = create(:user)

    @repo.add_member(@user2)
    @repo.add_member(@user3)
    @private_repo.add_member(@user3)
    @private_fork_before_transfer = create(:fork_repository, forker: @user3, fork_repo: @private_repo)
    @private_org_repo = create(:private_repository, owner: @org, from_example: :simple)
    @team = create :team, organization: @org
    @team.add_repository @private_org_repo, :pull
    @team.add_member @user4
    @team.add_member @user5
    @private_org_repo.add_member(@user4)
    @private_org_repo.add_member(@user5)
    @private_fork = create(:fork_repository, forker: @user4, fork_repo: @private_org_repo)
    @public_fork = create(:fork_repository, forker: @user4, fork_repo: @repo)

    @public_org_repo = create(:repository, owner: @org)
    @public_org_fork = create(:fork_repository, forker: @user4, fork_repo: @public_org_repo)
    @public_grandchild = create(:fork_repository, forker: @user5, fork_repo: @public_org_fork)

    @stranger = create(:user)
    @stranger_repo = create(:repository, owner: @stranger)
    example_repo_snapshot
  end

  setup do
    example_repo_restore

    GitHub.stubs(:actions_enabled?).returns(true)
  end

  # NOTE: Repository#can_transfer_ownership? tests live in
  # repository_can_transfer_ownership_test.rb

  test "fails if the target user already has a repo with the same name" do
    refute @repo.transfer_ownership_to(@user2, actor: @user)
  end

  test "fails if the target user already has a repo with the same new name" do
    repo = create(:repository, owner: @user2, name: "new-name")
    refute @repo.transfer_ownership_to(@user2, actor: @user, new_name: repo.name)

    # works if the new name is different
    assert @repo.transfer_ownership_to(@user2, actor: @user, new_name: "new-name-2")
  end

  test "allows rename during transfer to a name that's taken in the source, from a name that's taken in the destination" do
    # we'd like to transfer this repo and give it the name "new-name" for the new owner
    repo = create(:repository, owner: @user, name: "foo")
    new_name = "new-name"

    # we can't rename to the desired new name before transfer,
    # since the new name is already used by the source owner
    source_conflicting_repo = create(:repository, owner: @user, name: new_name)

    # we also can't transfer the repo as-is and then rename,
    # since the *current* name is used by the destination owner
    destination_conflicting_repo = create(:repository, owner: @user2, name: repo.name)

    # to get the desired repo name we can rename during transfer
    assert repo.transfer_ownership_to(@user2, actor: @user, new_name: new_name)
  end

  test "logs correct metrics for rename on transfer" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    assert @private_repo.transfer_ownership_to(@user2, actor: @user)
    assert @repo.transfer_ownership_to(@user2, actor: @user, new_name: "foo")

    assert_equal 2, GitHub.dogstats.increments("repository.transfer", tags: ["status:succeeded"]).size
    assert_equal 1, GitHub.dogstats.increments("repository.transfer", tags: ["status:succeeded", "rename:true"]).size
  end

  test "fails if the target user already has a repo in the same network" do
    GitHub.context.push(actor_id: @user.id)
    @repo.rename("something-else")
    refute @public_fork.transfer_ownership_to(@user, actor: @user)
  end

  test "succeeds if the target org already has a repo in the same network" do
    GitHub.context.push(actor_id: @user.id)
    @repo.rename("something-else")
    @org_fork, status = @repo.fork(forker: @user, org: @org, name: "something-else")
    assert @public_fork.transfer_ownership_to(@org, actor: @user)
  end

  test "fails if the target user has no room in their plan for another private repo" do
    @full_user = create(:user, plan: "small")
    @full_user.plan.repos.times { create(:private_repository, owner: @full_user) }
    # @full_user has cached private repo counts:
    target = User.find(@full_user.id)
    refute @private_repo.async_transfer_ownership_to(target, actor: @user)
  end

  test "fails if the target user has blocked the user attempting the transfer" do
    @user.block(@user3)
    invalid_repo = create(:repository, owner: @user3)

    refute invalid_repo.transfer_ownership_to(@user, actor: @user3)
    refute invalid_repo.async_transfer_ownership_to(@user, actor: @user3)
  end

  test "finishing the transfer fails if the target user has no room in their plan for another private repo" do
    @full_user = create(:user, plan: "small")
    available_repos = @full_user.plan.repos
    (available_repos - 1).times { create(:private_repository, owner: @full_user) }

    transfer = RepositoryTransfer.create(
      requester: @private_repo.owner,
      repository: @private_repo,
      target: @full_user,
    )

    create(:private_repository, owner: @full_user)
    @full_user.reload
    assert_predicate @full_user, :at_private_repo_limit?

    original_owner = @private_repo.owner


    perform_enqueued_jobs do # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      assert_raises ActiveRecord::RecordInvalid do
        transfer.finish(@full_user)
      end
    end

    assert_equal ["#{@full_user} has no private repositories available in their subscription"], transfer.errors.full_messages
    assert RepositoryTransfer.find_by_id(transfer.id)
    assert_equal original_owner, @private_repo.reload.owner
  end

  test "succeeds if the target user can accept a private repo" do
    @private_user = create(:user, plan: "small")
    assert @private_repo.transfer_ownership_to(@private_user, actor: @user)
    assert_equal_owner @private_user, @private_repo.owner
  end

  test "unpublishes pages if the target user is on a free plan", skip_enterprise: true do
    GitHub.flipper[:pages_soft_deletion].disable
    new_owner = create(:user, plan: "free")
    page = create(:page, repository: @private_repo)
    assert @private_repo.page
    assert @private_repo.transfer_ownership_to(new_owner, actor: @user)
    assert_equal_owner new_owner, @private_repo.owner
    assert_nil @private_repo.reload.page
  end


  test "removes protected branch rules if the target user is on a free plan" do
    new_owner = create(:user, plan: "free")
    protected_branch = create(:protected_branch, repository: @private_repo)
    assert @private_repo.protected_branches
    assert @private_repo.transfer_ownership_to(new_owner, actor: @user)
    assert_equal_owner new_owner, @private_repo.owner
    assert_empty @private_repo.reload.protected_branches
  end

  test "removes protected tag rules if the target user is on a free plan" do
    new_owner = create(:user, plan: "free")
    @private_repo.create_tag_protection_state(pattern: "*")
    refute_empty @private_repo.tag_protection_states
    assert @private_repo.transfer_ownership_to(new_owner, actor: @user)
    assert_equal_owner new_owner, @private_repo.owner
    assert_empty @private_repo.reload.tag_protection_states
  end

  [true, false].each do |branch_protections_enabled|
    test "removes protected branch bypassers (branch protections enabled: #{branch_protections_enabled})" do
      target = create(:user, plan: "small")
      create(:protected_branch, name: "main", repository: @repo)
      create(:protected_branch, name: "develop", repository: @repo)

      @repo.protected_branches.each do |protected_branch|
        protected_branch.enable_blocked_force_pushes
        protected_branch.replace_branch_actor_allowances(:force_push, user_ids: [@user.id], team_ids: nil, integration_ids: nil)
        protected_branch.save!
      end

      assert @repo.protected_branches.flat_map { |pb| pb.branch_actor_allowances_for_policy(:force_push) }.any?

      BranchProtectionsConfig.new(@repo).disable_branch_protection(actor: @user) unless branch_protections_enabled

      @repo.transfer_ownership_to(target, actor: @user)

      assert_equal_owner target, @repo.owner
      assert_equal 2, @repo.protected_branches.size
      assert @repo.protected_branches.reload.flat_map(&:branch_actor_allowances).empty?
    end
  end

  [true, false].each do |branch_protections_enabled|
    test "removes protected branch bypassers for org-owned repo (branch protections enabled: #{branch_protections_enabled})" do
      org = create(:organization)
      org.add_member(@user)
      org_repo = create(:repository, owner: org)

      org_repo.add_member(@user, action: :write)

      create(:protected_branch, name: "main", repository: org_repo)
      create(:protected_branch, name: "develop", repository: org_repo)

      org_repo.protected_branches.each do |protected_branch|
        protected_branch.enable_required_pull_request_reviews(bypass_pull_request_allowances: { "users" => [@user.login] }, dismissal_restrictions: { "users" => [@user.login] })
        protected_branch.enable_blocked_force_pushes
        protected_branch.replace_branch_actor_allowances(:force_push, user_ids: [@user.id], team_ids: nil, integration_ids: nil)
        protected_branch.update_restrictions(users: [@user.login], entry_point: :test_case)
        protected_branch.save!
      end

      assert org_repo.protected_branches.reload.flat_map(&:authorized_actor_names).any?
      assert org_repo.protected_branches.flat_map { |pb| pb.branch_actor_allowances_for_policy(:pull_request) }.any?
      assert org_repo.protected_branches.flat_map { |pb| pb.branch_actor_allowances_for_policy(:force_push) }.any?
      assert org_repo.protected_branches.flat_map(&:review_dismissal_allowances).any?
      assert_equal org_repo.protected_branches.size, org_repo.protected_branches.to_a.count(&:has_authorized_actors?)

      BranchProtectionsConfig.new(@repo).disable_branch_protection(actor: @user) unless branch_protections_enabled

      org_repo.transfer_ownership_to(@org, actor: @user)

      assert_equal_owner @org, org_repo.owner
      assert_equal @org, org_repo.organization

      protected_branches = org_repo.protected_branches.reload.to_a

      assert_equal 2, protected_branches.size
      assert protected_branches.flat_map(&:authorized_actor_names).empty?
      assert protected_branches.flat_map(&:branch_actor_allowances).empty?
      assert protected_branches.flat_map(&:review_dismissal_allowances).empty?
      assert_equal protected_branches.size, protected_branches.count(&:has_authorized_actors?)
    end
  end

  test "does not enable new protected branch bypass settings for org-owned repo" do
    org = create(:organization)
    org.add_member(@user)
    org_repo = create(:repository, owner: org)

    org_repo.add_member(@user, action: :write)

    create(:protected_branch, name: "main", repository: org_repo)
    create(:protected_branch, name: "develop", repository: org_repo)

    org_repo.transfer_ownership_to(@org, actor: @user)

    assert_equal_owner @org, org_repo.owner
    assert_equal @org, org_repo.organization

    protected_branches = org_repo.protected_branches.reload.to_a

    assert_equal 2, protected_branches.size
    assert_equal protected_branches.size, protected_branches.count { |pb| pb.block_force_pushes_enforcement_level == "everyone" }
    assert_equal protected_branches.size, protected_branches.count { |pb| pb.pull_request_reviews_enforcement_level == "off" }
    assert_equal 0, protected_branches.count(&:authorized_dismissal_actors_only?)
    assert_equal 0, protected_branches.count(&:has_authorized_actors?)
  end

  test "removes ruleset bypassers" do
    org = create(:organization)
    org.add_member(@user)
    team = create(:team, organization: org, privacy: :closed)

    org_repo = create(:repository, owner: org)
    org_repo.add_team(team, action: :admin)

    rulesets = create_list(:repository_ruleset, 2, :example_ruleset, source: org_repo, bypass_actors: [
      RepositoryRulesetBypassActor.new(
        actor: team
      )
    ])

    assert org_repo.rulesets.reload.flat_map(&:bypass_actors).any?

    org_repo.transfer_ownership_to(@org, actor: @user)

    assert_equal_owner @org, org_repo.owner
    assert_equal @org, org_repo.organization
    assert_equal rulesets.size, org_repo.rulesets.size
    assert org_repo.rulesets.reload.flat_map(&:bypass_actors).empty?
  end

  test "transfer succeeds if rulesets are invalid" do
    old_org = create(:organization)
    old_org.add_member(@user)
    repo = create(:repository, owner: old_org)

    # create a ruleset and make it invalid
    ruleset = create(:repository_ruleset, :example_ruleset, source: repo)
    ruleset.update_column(:name, "")
    refute ruleset.reload.valid?

    # transfer should still succeed
    repo.transfer_ownership_to(@org, actor: @user)

    assert_equal_owner @org, repo.owner
    assert_equal @org, repo.organization
  end

  test "finishing the transfer is fine if the target user can accept a private repo" do
    @private_user = create(:user, plan: "small")

    transfer = RepositoryTransfer.create!(
      requester: @private_repo.owner,
      repository: @private_repo,
      target: @private_user,
    )

    perform_enqueued_jobs(only: [TransferRepositoryJob, RepositoryOrchestrationJob]) do
      transfer.finish(@private_user)
    end

    assert_nil RepositoryTransfer.find_by_id(transfer.id)
    assert_equal @private_user, @private_repo.reload.owner
  end

  test "changes the owner" do
    @repo.transfer_ownership_to(@org, actor: @user)
    assert_equal_owner @org, @repo.owner
    assert_equal @org, @repo.organization
  end

  test "changes the name when orchestration is enabled" do
    @repo.transfer_ownership_to(@org, actor: @user, new_name: "foo")
    assert_equal_owner @org, @repo.owner
    assert_equal @org, @repo.organization
    assert_equal "foo", @repo.name
  end

  test "updates the registry packages" do
    request_id = SecureRandom.uuid
    GitHub.context.push({ request_id: request_id })

    example_repo :pages, @repo

    @registry_package = Registry::Package.new name: "test1",
      repository_id: @repo.id, package_type: :npm

    @release = create :release, repository: @repo, tag_name: "v1", author: @user,
      state: :published, created_at: 1.month.ago, body: "*version 1*"

    version = @registry_package.package_versions.build version: "1.0",
      release: @release, author: @user

    version.files.build filename: "one", size: 1
    version.files.build filename: "two", size: 1

    version_deleted = @registry_package.package_versions.build version: "1.1", author: @user

    version_deleted.files.build filename: "one", size: 1

    @registry_package.save!

    version_deleted.delete!(force_delete: true)
    reset_hydro if GitHub.hydro_enabled?

    assert_equal @repo.owner.id, @registry_package.owner_id

    transferred_at = Time.now.utc
    Timecop.freeze(transferred_at) do
      @repo.transfer_ownership_to(@org, actor: @user)
    end
    @registry_package.reload

    assert_equal @org.id, @registry_package.owner_id


    if GitHub.hydro_enabled?
      message = {
        request_context: Hydro::EntitySerializer.request_context({ request_id: request_id }),
        actor: Hydro::EntitySerializer.user(@user),
        package: Hydro::EntitySerializer.package(@registry_package, total_size: 2),
        transferred_at: transferred_at,
        storage_service: { name: "AWS_S3" },
        user_agent: "",
        repository: Hydro::EntitySerializer.repository(@repo),
        previous_repository: nil,
        previous_owner_org: nil,
        previous_owner_user: Hydro::EntitySerializer.user(@user),
        previous_owner_id: @user.id,
        previous_owner_global_id: @user.global_relay_id,
        event_id: request_id,
      }

      assert_hydro_messages(count: 1, schema: "package_registry.v0.PackageTransferred")
      assert_hydro_published(message, schema: "package_registry.v0.PackageTransferred")
    end
  end

  test "maintains watched status" do
    assert @user.watching_repo?(@repo)
    @repo.transfer_ownership_to(@org, actor: @user)
    assert @user.reload.watching_repo?(@repo.reload)
  end

  test "changes the plan owner" do
    @repo.transfer_ownership_to(@org, actor: @user)
    @repo.reload
    assert_equal @org, @repo.plan_owner
  end

  test "changes the plan owner of forks as well" do
    @private_repo.transfer_ownership_to(@org, actor: @user)
    @private_repo.reload
    assert_equal @org, @private_repo.plan_owner

    @private_fork_before_transfer.reload
    assert_equal @org, @private_fork_before_transfer.plan_owner
  end

  test "transfers collaborators if the destination user is an org" do
    @repo.transfer_ownership_to(@org, actor: @user)
    assert_same_elements [@user, @user2, @user3], @repo.reload.members
  end

  test "transfers collaborators if the desination user is a user" do
    assert_able @user3, :write, @private_repo
    @private_repo.transfer_ownership_to(@user2, actor: @user)
    assert_includes @private_repo.members, @user3
    assert_able @user3, :write, @private_repo
  end

  test "removes teams" do
    assert_equal 1, @private_org_repo.teams.size
    @private_org_repo.transfer_ownership_to(@user, actor: @user)
    assert_equal 0, @private_org_repo.reload.teams.size
  end

  test "removes teams with maintain/triage" do
    maintain_team = create(:team, organization: @org)
    maintain_team.add_repository(@private_org_repo, :maintain)
    assert_equal 2, @private_org_repo.teams.size
    @private_org_repo.transfer_ownership_to(@user, actor: @user)
    assert_equal 0, @private_org_repo.reload.teams.size
    assert_empty UserRole.where(actor_id: maintain_team.id, actor_type: "Team", target_id: @private_org_repo.id, target_type: "Repository")
  end

  test "adjusts grandchildren organization_ids after successful transfer" do
    assert @public_org_repo.transfer_ownership_to(@user, actor: @user)
    assert_equal_owner @user, @public_org_repo.owner
    assert_nil @public_org_repo.reload.organization_id
    assert_nil @public_org_fork.reload.organization_id
    assert_nil @public_grandchild.reload.organization_id
  end

  test "adds specified teams if the destination user is an org" do
    new_org = create(:organization)
    new_org_team = create :team, organization: new_org
    new_org_team.add_member @user4

    @private_org_repo.transfer_ownership_to(new_org, actor: @user, target_teams: [new_org_team])

    assert_equal [new_org_team], @private_org_repo.reload.teams
  end

  test "retains collaborators when transferring from a user to an org" do
    collaborator = create(:user, login: "collaborator")
    @private_repo.add_member(collaborator)

    new_org = create(:organization, login: "destination")
    @private_repo.transfer_ownership_to(new_org, actor: @user)

    assert_equal_owner new_org, @private_repo.owner
    assert_includes @private_repo.members, collaborator
    assert_able collaborator, :write, @private_repo
  end

  test "retains repo owner as collaborator when transferring from a user to an org" do
    assert_equal_owner @user, @private_repo.owner

    new_org = create(:organization, login: "destination")
    @private_repo.transfer_ownership_to(new_org, actor: @user)

    assert_equal_owner new_org, @private_repo.owner
    assert_includes @private_repo.members, @user
    assert_able @user, :write, @private_repo
  end

  test "retains collaborators when transferring from an org to an org" do
    read_collaborator  = create(:user, login: "read-collaborator")
    write_collaborator = create(:user, login: "write-collaborator")
    admin_collaborator = create(:user, login: "admin-collaborator")
    @private_org_repo.add_member(read_collaborator, action: :read)
    @private_org_repo.add_member(write_collaborator, action: :write)
    @private_org_repo.add_member(admin_collaborator, action: :admin)

    new_org = create(:organization, login: "destination")
    @private_org_repo.transfer_ownership_to(new_org, actor: @user)

    assert_equal_owner new_org, @private_org_repo.owner

    assert_includes @private_org_repo.members, read_collaborator
    assert_able read_collaborator, :read, @private_org_repo
    refute_able read_collaborator, :write, @private_org_repo

    assert_includes @private_org_repo.members, write_collaborator
    assert_able write_collaborator, :write, @private_org_repo
    refute_able write_collaborator, :admin, @private_org_repo

    assert_includes @private_org_repo.members, admin_collaborator
    assert_able admin_collaborator, :admin, @private_org_repo
  end

  test "retains write/admin collaborators and updates permissions to push when transferring from an org to a user" do
    read_collaborator  = create(:user, login: "read-collaborator")
    write_collaborator = create(:user, login: "write-collaborator")
    admin_collaborator = create(:user, login: "admin-collaborator")
    @private_org_repo.add_member(read_collaborator, action: :read)
    @private_org_repo.add_member(write_collaborator, action: :write)
    @private_org_repo.add_member(admin_collaborator, action: :admin)

    new_org = create(:organization, login: "destination")
    @private_org_repo.transfer_ownership_to(@user, actor: @user)

    assert_equal_owner @user, @private_org_repo.owner

    refute_includes @private_org_repo.members, read_collaborator
    refute_able read_collaborator, :read, @private_org_repo

    assert_includes @private_org_repo.members, write_collaborator
    assert_able write_collaborator, :write, @private_org_repo
    refute_able write_collaborator, :admin, @private_org_repo

    assert_includes @private_org_repo.members, admin_collaborator
    assert_able admin_collaborator, :write, @private_org_repo
    refute_able admin_collaborator, :admin, @private_org_repo
  end

  test "removes triage/maintain when transferring from an org to a user" do
    triage_collab = create(:user, login: "triage-collaborator")
    maintain_collab = create(:user, login: "maintain-collaborator")
    @private_org_repo.add_member(triage_collab, action: :triage)
    @private_org_repo.add_member(maintain_collab, action: :maintain)

    new_org = create(:organization, login: "destination")
    @private_org_repo.transfer_ownership_to(@user, actor: @user)

    assert_equal_owner @user, @private_org_repo.owner

    refute_equal :triage, @private_org_repo.direct_role_for(triage_collab)
    refute_includes @private_org_repo.members, triage_collab

    refute_equal :maintain, @private_org_repo.direct_role_for(maintain_collab)
    assert_equal :write, @private_org_repo.direct_role_for(maintain_collab)
  end

  test "removes the org's default repository permission ability when transferring from an org" do
    refute_equal :none, @org.default_repository_permission

    org_member = create(:user, login: "org-member")
    @org.add_member(org_member)

    # Org member can read repo because of the default repo permission.
    assert_able org_member, :read, @private_org_repo

    @private_org_repo.transfer_ownership_to(@user, actor: @user)

    # Org member can no longer read repo because it's no longer owned by the org
    # so the default repo permission no longer applies.
    refute_able org_member, :read, @private_org_repo
  end

  test "removes org-association if the destination user is a user" do
    @repo.transfer_ownership_to(@org, actor: @user)
    assert_equal @org, @repo.organization

    @repo.transfer_ownership_to(@user3, actor: @user)
    assert_nil @repo.organization
  end

  test "switches owner and collaborator status if the destination user is not an org" do
    assert_equal_owner @user, @repo.owner
    assert  @repo.members.include?(@user3)
    refute @repo.members.include?(@user)

    @repo.transfer_ownership_to(@user3, actor: @user)
    @repo.reload

    assert_equal_owner @user3, @repo.owner
    refute @repo.members.include?(@user3)
    assert_includes @repo.members, @user

    assert User.find(@user.id)  # sanity check to ensure members.delete(user)
    assert User.find(@user3.id) # only removes from the collection
  end

  test "doesn't add any validation failures to the repo record when transferring an org-owned repo" do
    @private_org_repo.transfer_ownership_to(@user, actor: @user)
    assert_empty @private_org_repo.errors
  end

  test "new owner doesn't star the repo" do
    refute @repo.starred_by?(@org)
    @repo.transfer_ownership_to(@org, actor: @user)
    refute @repo.starred_by?(@org)
  end

  test "forces users to unstar private repos when transferred to an org" do
    # @user is a collab and on the Owners team
    # @user3 is a collab, but not on the Owners team
    @user.star @private_repo
    @user3.star @private_repo
    assert @private_repo.members.include?(@user3)
    assert @private_repo.starred_by?(@user3)
    @private_repo.transfer_ownership_to @org, actor: @user

    assert @private_repo.starred_by?(@user)
  end

  test "does nothing for public stargazers when transferred to an org" do
    @user.star @repo
    @user3.star @repo
    assert @repo.members.include?(@user3)
    assert @repo.starred_by?(@user3)
    @repo.transfer_ownership_to @org, actor: @user

    assert @repo.starred_by?(@user)
    assert @repo.starred_by?(@user3)
  end

  test "removes assignees to issues who will no longer have access" do
    issue = create :issue, title: "hi1", repository: @repo, user: @user
    issue2 = create :issue, title: "hi2", repository: @repo, user: @user
    issue2_updated_at = issue2.updated_at
    assert_equal @repo, issue.repository
    assert issue.assignable_to?(@user2)
    issue.assignee = @user2
    issue.save!
    assert_equal @user2, issue.reload.assignee

    assert @repo.transfer_ownership_to @org, actor: @user
    @repo.reload
    issue.reload

    assert issue.valid?
    # ensure other issues don't get touched
    assert_equal issue2_updated_at, issue2.updated_at
  end

  test "preserves collaborator abilitites when transferring to an org" do
    @repo.add_member @stranger
    assert_able @stranger, :write, @repo

    # @stranger has no relationship with @org
    refute_able @stranger, :read, @org

    @repo.transfer_ownership_to @org, actor: @user
    assert_able @stranger, :write, @repo
    refute_able @stranger, :read, @org
  end

  test "removes collaborators on private forks when transferring a private repo to an organization" do
    @private_repo.add_member @user2
    private_fork = create(:fork_repository, forker: @user2, fork_repo: @private_repo)
    private_fork.add_member @user3

    @private_repo.transfer_ownership_to @org, actor: @user
    private_fork.reload

    assert_same_elements [@user, @user2, @user3], @private_repo.members
    assert_equal [], private_fork.members
  end

  test "preserves collaborators on public forks when transferring a public repo to an organization" do
    public_fork = create(:fork_repository, forker: @user2, fork_repo: @repo)
    public_fork.add_member @user3
    @repo.transfer_ownership_to @org, actor: @user

    assert_same_elements [@user, @user2, @user3], @repo.members
    assert_same_elements [@user3], public_fork.members
  end

  test "changes PullRequest#base_user to new owner" do
    pull = make_pull_request
    repo = pull.repository

    repo.transfer_ownership_to(@org, actor: @user)
    assert_equal_owner @org, repo.owner
    assert_equal @org, pull.reload.base_user
  end

  test "unsubscribes those who no longer have access to the repository" do
    # @user is a collab and on the Owners team
    # @user3 is a collab, but not on the Owners team
    @user.watch_repo @private_repo
    @user3.watch_repo @private_repo
    assert @private_repo.members.include?(@user3)
    assert @user3.watching_repo?(@private_repo)

    @private_repo.transfer_ownership_to @org, actor: @user

    assert @user.watching_repo?(@private_repo)
    assert @user3.watching_repo?(@private_repo)
  end

  test "unsubscribes users who were only watching an issue in a repository" do
    issue = create :issue, :subscribed_author, repository: @private_repo, user: @user
    issue.subscribe @user3, :manual

    assert GitHub.newsies.subscription_status(@user, @private_repo, issue).value.subscribed?
    assert GitHub.newsies.subscription_status(@user3, @private_repo, issue).value.subscribed?

    @private_repo.transfer_ownership_to @org, actor: @user

    assert GitHub.newsies.subscription_status(@user, @private_repo, issue).subscribed?
  end

  test "removes user subscriptions when transferring a private repository to another org" do
    org1 = create(:organization)
    org2 = create(:organization)

    org1.add_admin(@user)
    repo = create(:private_repository, owner: org1)
    @user.watch_repo(repo)

    assert_predicate GitHub.newsies.subscription_status(@user, repo), :valid?

    only = [RepositoryOrchestrationJob, Newsies::DeleteAllForListAndUsersJob, NewsiesPurgeSubscribersJob]

    perform_enqueued_jobs(only: only) do
      perform_enqueued_hydro_jobs(only: [HydroCorrectWatchersRepositoryTransferredJob], allowed_primary_query_count: 1) do
        repo.transfer_ownership_to(org2, actor: @user)
      end
    end

    refute_predicate GitHub.newsies.subscription_status(@user, repo), :valid?
  end

  test "does not remove user subscriptions when transferring a public repository to another org" do
    org1 = create(:organization)
    org2 = create(:organization)

    org1.add_admin(@user)
    repo = create(:repository, owner: org1)
    @user.watch_repo(repo)

    assert_predicate GitHub.newsies.subscription_status(@user, repo), :valid?

    repo.transfer_ownership_to(org2, actor: @user)

    assert_predicate GitHub.newsies.subscription_status(@user, repo), :valid?
  end

  test "revokes admin ability on forks from previous org owner admins" do
    new_owner = create :user, plan: "small"
    assert_able @user, :admin, @private_fork # org admin can admin a fork
    assert @private_org_repo.transfer_ownership_to(new_owner, actor: @user)
    refute_able @user, :admin, @private_org_repo
    refute_able @user, :admin, @private_fork.reload
  end

  test "grants admin ability on forks to org owners when transferring a repo into an org" do
    new_owner = create(:user)
    new_org = create :organization, plan: "bronze", admin: new_owner
    new_org.add_admin(@user4)
    assert @private_org_repo.transfer_ownership_to(new_org, actor: @user)
    assert_able new_owner, :admin, @private_org_repo
    assert_able new_owner, :admin, @private_fork.reload
  end

  test "transfers are audited" do
    old_name_with_owner = @repo.name_with_owner

    events = subscribe("repo.transfer")
    assert @repo.transfer_ownership_to(@user3, actor: @user)

    expected_payload = {
      actor: @user.login,
      actor_id: @user.id,
      fork_source: @repo.name_with_owner,
      fork_source_id: @repo.id,
      old_user: @user.login,
      old_user_id: @user.id,
      owner: @user3.login,
      owner_id: @user3.id,
      owner_is_org: false,
      owner_was_org: false,
      repo: @repo.name_with_owner,
      repo_id: @repo.id,
      public_repo: @repo.public?,
      repo_was: old_name_with_owner,
      user: @user3.login,
      user_id: @user3.id,
      visibility: :public,
    }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "generates a transfer_outgoing audit event for org target" do
    old_name_with_owner = @repo.name_with_owner
    org = create(:organization)
    org_owner = org.admin
    org.add_member(@user)
    transfer = create(:repository_transfer,
      repository: @repo,
      requester: @user,
      target: org,
    )

    expected_payload = {
      repo: "#{@user.login}/#{@repo.name}",
      repo_id: @repo.id,
      public_repo: @repo.public?,
      visibility: :public,
      user: @user.login,
      user_id: @user.id,
      new_owner: org.login,
      new_owner_id: org.id,
      new_nwo: "#{org.login}/#{@repo.name}",
      actor: @user.login,
      actor_id: @user.id,
    }

    events = subscribe("repo.transfer_outgoing")
    assert @repo.transfer_ownership_to(org, actor: org_owner)

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "generates a transfer_outgoing audit event for user target" do
    old_name_with_owner = @repo.name_with_owner
    transfer = create(:repository_transfer,
      repository: @repo,
      requester: @user,
      target: @user3,
    )

    expected_payload = {
      repo: "#{@user.login}/#{@repo.name}",
      repo_id: @repo.id,
      public_repo: @repo.public?,
      visibility: :public,
      user: @user.login,
      user_id: @user.id,
      new_owner: @user3.login,
      new_owner_id: @user3.id,
      new_nwo: "#{@user3.login}/#{@repo.name}",
      actor: @user.login,
      actor_id: @user.id,
    }

    events = subscribe("repo.transfer_outgoing")
    assert @repo.transfer_ownership_to(@user3, actor: @user3)

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "generates a transfer_outgoing audit event for user target from org" do
    org = create(:organization, admin: @user)
    repo = create(:repository, owner: org)
    old_name_with_owner = @repo.name_with_owner
    transfer = create(:repository_transfer,
      repository: repo,
      requester: @user,
      target: @user,
    )

    expected_payload = {
      repo: "#{org.login}/#{repo.name}",
      repo_id: repo.id,
      public_repo: repo.public?,
      visibility: :public,
      org: org.login,
      org_id: org.id,
      new_owner: @user.login,
      new_owner_id: @user.id,
      new_nwo: "#{@user.login}/#{repo.name}",
      actor: @user.login,
      actor_id: @user.id,
    }

    events = subscribe("repo.transfer_outgoing")
    assert repo.transfer_ownership_to(@user, actor: @user)

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "generates a transfer_outgoing audit event when no transfer record exists" do
    old_name_with_owner = @repo.name_with_owner
    assert_nil @repo.pending_transfer

    expected_payload = {
      repo: "#{@user.login}/#{@repo.name}",
      visibility: :public,
      user: @user.login,
      user_id: @user.id,
      new_owner: @user3.login,
      new_owner_id: @user3.id,
      new_nwo: "#{@user3.login}/#{@repo.name}",
      repo_id: @repo.id,
      public_repo: @repo.public?,
    }

    events = subscribe("repo.transfer_outgoing")
    assert @repo.transfer_ownership_to(@user3, actor: @user3)

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "removes inaccessible forks and doesn't add them as dependents when transferring between orgs" do
    org = create(:organization, plan: "silver")
    org.allow_private_repository_forking(actor: org.admins.first)
    org.update_default_repository_permission(:none, actor: org.admins.first)
    private_repo = create(:private_repository, owner: org)
    team = create(:team, organization: org)

    org2 = create(:organization, plan: "silver")
    org2.update_default_repository_permission(:none, actor: org2.admins.first)
    user = create(:user)

    team.add_member user
    team.add_repository private_repo, :pull
    fork = create(:fork_repository, forker: user, fork_repo: private_repo)

    private_repo.transfer_ownership_to(org2, actor: user)
    private_repo.reload

    assert fork.reload.deleted?
    refute_able org2.admins.first, :admin, fork
  end

  test "preserves forks of those on teams of new org" do
    org = create(:organization, plan: "silver")
    org.allow_private_repository_forking(actor: org.admins.first)
    org.update_default_repository_permission(:none, actor: org.admins.first)
    private_repo = create(:private_repository, owner: org)
    team = create(:team, organization: org)

    user = create(:user)
    user2 = create(:user)

    team.add_member user
    team.add_member user2
    team.add_repository private_repo, :pull

    original_fork = create(:fork_repository, forker: user, fork_repo: private_repo)
    create(:fork_repository, forker: user2, fork_repo: private_repo)

    assert private_repo.forks.collect(&:name_with_owner).include? "#{user.login}/#{private_repo.name}"
    assert private_repo.forks.collect(&:name_with_owner).include? "#{user2.login}/#{private_repo.name}"

    new_org = create(:organization, plan: "silver")
    new_org.update_default_repository_permission(:none, actor: new_org.admins.first)
    new_org_team = create :team, organization: new_org
    new_org_team.add_member user

    private_repo.transfer_ownership_to(new_org, actor: user, target_teams: [new_org_team])

    private_repo.reload

    assert private_repo.forks.collect(&:name_with_owner).include? "#{user.login}/#{private_repo.name}"
    refute private_repo.forks.collect(&:name_with_owner).include? "#{user2.login}/#{private_repo.name}"
  end

  test "grants admin permissions to new org admins when transferring an org-owned fork to another org" do
    root_owner = create(:user)
    repo       = create(:repository, owner: root_owner)

    source_org   = create(:organization)
    collaborator = create(:user)
    team         = create :team, organization: source_org, permission: "admin"

    team.add_member collaborator

    org_fork, status = repo.fork(forker: collaborator, org: source_org)
    assert_equal :created, status

    team.add_repository org_fork, :admin

    dest_org = create(:organization)
    dest_admin = create(:user)
    dest_org.add_admin(dest_admin)

    assert_able collaborator, :read, org_fork
    assert_able source_org.admins.first, :admin, org_fork

    # make the repo transfer play nice with routing
    FileUtils.mkdir_p repo.shard_path
    FileUtils.mkdir_p org_fork.shard_path

    assert org_fork.transfer_ownership_to(dest_org, actor: root_owner)

    org_fork.reload

    assert_able dest_admin, :admin, org_fork
  end

  test "updates LFS status when transferring repository with LFS objects" do
    GitHub.flipper[:lfs_metered_billing_vnext].enable
    Billing::Platform::Api::Client.any_instance.stubs(:get_watermark_level).returns({ quantity: 50 })

    source = create(:user)
    target = create(:user)

    file1 = create :asset, size: 500.megabytes
    file2 = create :asset, size: 600.megabytes

    Timecop.freeze(DateTime.parse("2023-02-01 04:05:06 UTC")) do
      source.build_asset_status!

      plain_repo = create(:repository, owner: source)
      lfs_repo_1 = create(:repository, owner: source)
      create(:media_blob, asset: file1, repository_network: lfs_repo_1.network, state: 3)

      lfs_repo_2 = create(:repository, owner: source)
      create(:media_blob, asset: file2, repository_network: lfs_repo_2.network, state: 3)

      source.reload.asset_status.rebuild
      source.reload.asset_status.reload
      assert source.asset_status.storage > 1, "storage: #{source.asset_status.storage}"
      refute target.asset_status

      assert lfs_repo_1.transfer_ownership_to(target, actor: source)

      unless GitHub.enterprise?
        assert_equal 1, hydro_message_count(schema: "billingplatform.v1.Usage")
        assert_hydro_published({
            sku: "git_lfs_storage",
            quantity: -50.0,
            usage_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i),
            source_uri: "gid://git-hub/reset/#{lfs_repo_1.id}",
            entity: { customer_id: source.customer.id, organization_id: 0, repo_id: lfs_repo_1.id, actor_id: source.id }
          },
          schema: "billingplatform.v1.Usage",
          count: 1
        )
      end

      assert source.asset_status.reload
      assert source.asset_status.storage < 1, "storage: #{source.asset_status.storage}"
      assert source.asset_status.storage > 0.5, "storage: #{source.asset_status.storage}"

      assert target.reload.asset_status
      assert target.asset_status.storage > 0.4, "storage: #{target.asset_status.storage}"
    end
  end

  test "updates LFS status when transferring repository without LFS objects" do
    source = create(:user)
    target = create(:user)

    file1 = create :asset, size: 500.megabytes

    source.build_asset_status!

    plain_repo = create(:repository, owner: source)
    lfs_repo_1 = create(:repository, owner: source)
    create(:media_blob, asset: file1, repository_network: lfs_repo_1.network, state: 3)

    source.reload.asset_status.rebuild
    source.reload.asset_status.reload

    old_status_storage = source.asset_status.storage

    assert source.asset_status.storage > 0.4, "storage: #{source.asset_status.storage}"
    refute target.asset_status

    assert plain_repo.transfer_ownership_to(target, actor: source)

    assert_equal old_status_storage, source.asset_status.reload.storage
    refute target.asset_status
  end

  test "doesn't blow up when transferring if previous owner has no asset status" do
    source = create(:user)
    target = create(:user)

    file1 = create :asset, size: 500.megabytes
    lfs_repo_1 = create(:repository, owner: source)
    create(:media_blob, asset: file1, repository_network: lfs_repo_1.network, state: 3)

    source.reload.asset_status.destroy

    refute source.reload.asset_status
    refute target.asset_status

    assert_nothing_raised do
      assert lfs_repo_1.transfer_ownership_to(target, actor: source)
    end
  end

  test "removes the repository from all of the integration installations it belongs to" do
    integration_1 = create(:integration, default_permissions: { "metadata" => :read })
    integration_2 = create(:integration, default_permissions: { "metadata" => :read })

    installation_1 = integration_1.install_on(
      @private_repo.owner,
      repositories: [@private_repo, @repo],
      installer: @user,
      entry_point: :test_case
    ).installation

    installation_2 = integration_2.install_on(
      @private_repo.owner,
      repositories: [@private_repo, @repo],
      installer: @user,
      entry_point: :test_case
    ).installation

    private_repo_installations = IntegrationInstallation.with_repository(@private_repo)
    assert_includes private_repo_installations, installation_1
    assert_includes private_repo_installations, installation_2

    @private_repo.transfer_ownership_to(@org, actor: @user)

    private_repo_installations = IntegrationInstallation.with_repository(@private_repo)
    refute_includes private_repo_installations, installation_1
    refute_includes private_repo_installations, installation_2

    # Make sure that the @repo still has access to the its installations.
    repo_installations = IntegrationInstallation.with_repository(@repo)
    assert_includes repo_installations, installation_1
    assert_includes repo_installations, installation_2
  end

  test "removes access to grants on transfer" do
    grant1 = make_user_programmatic_access_with_grant(
      requester: @private_repo.owner, permissions: { "metadata" => :read },
      repository_selection: :subset, repositories: [@private_repo, @repo]
    ).grant

    grant2 = make_user_programmatic_access_with_grant(
      requester: @private_repo.owner, permissions: { "metadata" => :read },
      repository_selection: :subset, repositories: [@private_repo, @repo]
    ).grant

    assert_same_elements [@private_repo.id, @repo.id], grant1.repository_ids
    assert_same_elements [@private_repo.id, @repo.id], grant2.repository_ids

    @private_repo.transfer_ownership_to(@org, actor: @user)

    assert_same_elements [@repo.id], grant1.repository_ids
    assert_same_elements [@repo.id], grant2.repository_ids
  end

  test "skips edit or removal of installation when installed on the target" do
    installation = make_integration_installation(target: @user, permissions: { "metadata" => :read })

    assert_predicate installation, :installed_on_all_repositories?

    @private_repo.transfer_ownership_to(@org, actor: @user)

    assert_predicate installation, :installed_on_all_repositories?
  end

  test "deletes the installation if the last repo is being transfered" do
    integration = create(:integration, default_permissions: { "metadata" => :read })

    installation = integration.install_on(
      @private_repo.owner,
      repositories: [@private_repo],
      installer: @user,
      entry_point: :test_case
    ).installation

    installations = IntegrationInstallation.with_repository(@private_repo)
    assert_includes installations, installation

    @private_repo.transfer_ownership_to(@org, actor: @user)

    installations = IntegrationInstallation.with_repository(@private_repo)
    refute_includes installations, installation

    refute IntegrationInstallation.where(id: installation.id).present?
  end

  context "transferring repos with integrations that can follow transfers" do
    test "installs the app on the new target and uninstalls from the previous one" do
      integration  = create_internal_app_with_capabilities(capabilities: { follow_repository_transfers: true })

      installation = integration.install_on(
        @user,
        repositories: [@private_repo],
        installer: @private_repo.owner,
        entry_point: :test_case
      ).installation

      # original target is user
      assert_equal @user.id, installation.target_id
      installations_on_repo = IntegrationInstallation.with_repository(@private_repo)
      assert_includes installations_on_repo, installation

      # only repo abilities
      pre_transfer_abilities = installation.abilities
      assert_equal 1, pre_transfer_abilities.count
      assert_equal @private_repo.id, pre_transfer_abilities.first.subject_id

      assert_empty IntegrationInstallation.with_target(@org)

      # transfer repo
      @private_repo.transfer_ownership_to(@org, actor: @private_repo.owner)

      # installation on initial target no longer exists
      assert_empty IntegrationInstallation.with_target(@user)

      # installation on new target exists
      new_target_installations = IntegrationInstallation.with_target(@org)
      assert_equal 1, new_target_installations.count
      assert_equal integration, new_target_installations.first.integration

      # Abilities records are the same since they only map installation --> repo
      # resources
      post_transfer_abilities = new_target_installations.first.abilities
      assert_equal 1, post_transfer_abilities.count

      assert_equal pre_transfer_abilities.first.subject_id,
                   post_transfer_abilities.first.subject_id
    end

    test "appends the repo to any existing installation on the new target, if the app is already installed" do
      integration  = create_internal_app_with_capabilities(capabilities: { follow_repository_transfers: true })

      # install Actions on the user transferring the repo
      installation = integration.install_on(
        @user,
        repositories: [@private_repo],
        installer: @private_repo.owner,
        entry_point: :test_case
      ).installation

      # install Actions on the new target
      integration.install_on(
        @org,
        repositories: [@private_org_repo],
        installer: @org.admins.first,
        entry_point: :test_case
      )

      assert_same_elements integration.installations.with_target(@org).first.repositories, [@private_org_repo]

      @private_repo.transfer_ownership_to(@org, actor: @private_repo.owner)

      assert_empty IntegrationInstallation.where(id: installation.id)
      assert_same_elements integration.installations.with_target(@org).first.repositories, [@private_repo, @private_org_repo]
    end

    test "uninstalls the app from the old owner even if the repo fails to be added to existing installations on the new owner" do
      integration  = create_internal_app_with_capabilities(capabilities: { follow_repository_transfers: true })

      # install Actions on the user transferring the repo
      installation = integration.install_on(
        @user,
        repositories: [@private_repo],
        installer: @private_repo.owner,
        entry_point: :test_case
      ).installation

      # install Actions on the new target
      org_installation = integration.install_on(
        @org,
        repositories: [@private_org_repo],
        installer: @org.admins.first,
        entry_point: :test_case
      ).installation

      assert_same_elements integration.installations.with_target(@org).first.repositories, [@private_org_repo]

      IntegrationInstallation::Editor.expects(:append).with(
        org_installation,
        repositories: [@private_repo],
        editor: @org,
        entry_point: :transfer_repository_orchestration_reinstall_integrations,
      ).returns(
        IntegrationInstallation::Editor::Result.failed("boom", "mocked-reason"),
      )

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @private_repo.transfer_ownership_to(@org, actor: @private_repo.owner)

      # Even if reinstalling the App fails, we should ensure the App is uninstalled
      # from the previous owner so it doesn't reference non owned repositories
      assert_empty IntegrationInstallation.where(id: installation.id)
      assert_same_elements integration.installations.with_target(@org).first.repositories, [@private_org_repo]
      assert_equal 1, GitHub.dogstats.increments("repository.reinstall_integration", tags: ["result:failed"]).size
    end

    test "keeps the app on the previous owner if it's installed in more than one repository" do
      integration  = create_internal_app_with_capabilities(capabilities: { follow_repository_transfers: true })

      another_user_repo = create(:repository, owner: @user)
      installation = integration.install_on(
        @user,
        repositories: [@private_repo, another_user_repo],
        installer: @private_repo.owner,
        entry_point: :test_case
      ).installation

      # Install Actions on the new target
      org_installation = integration.install_on(
        @org,
        repositories: [@private_org_repo],
        installer: @org.admins.first,
        entry_point: :test_case
      ).installation

      assert_same_elements integration.installations.with_target(@org).first.repositories, [@private_org_repo]

      @private_repo.transfer_ownership_to(@org, actor: @private_repo.owner)

      # Ensure Actions remains installed on the repo not being transferred
      refute_empty IntegrationInstallation.where(id: installation.id)
      assert_same_elements installation.reload.repositories, [another_user_repo]
      assert_same_elements integration.installations.with_target(@org).first.repositories, [@private_org_repo, @private_repo]
    end

    test "performs installation if installation repo has org permissions" do
      admin = create(:paid_user)
      integration  = create_internal_app_with_capabilities(permissions: { "metadata" => :read, "members" => :read }, capabilities: { follow_repository_transfers: true })

      org = create(:organization, admin: admin)
      member = create(:user)
      org.add_member(member)
      repo = create(:private_repository, owner: org)
      public_repo = create(:repository, owner: org)

      installation =
        integration.install_on(org, repositories: [repo], installer: admin, entry_point: :test_case).installation

      assert_same_elements [repo.id], installation.repository_ids
      assert_equal org.id, installation.target_id

      IntegrationInstallation.any_instance.stubs(:launch_github_app?).returns(true)

      # transfer repo
      repo.transfer_ownership_to(member, actor: repo.owner)

      # installation on initial target no longer exists
      old_target_installations = IntegrationInstallation.with_target(org)
      assert_empty old_target_installations

      # installation on new target exists
      new_target_installations = IntegrationInstallation.with_target(member)
      refute_empty new_target_installations
      assert_same_elements new_target_installations.first.repositories, [repo]
    end
  end

  test "deletes repo from old owner's pinned repositories if old owner is org" do
    profile = create(:profile, user: @org)
    public_repo = create(:repository, owner: @org)

    create :profile_pin, pinned_item: public_repo, profile: profile

    refute_empty @org.reload.pinned_repositories
    public_repo.transfer_ownership_to(@user, actor: @user)
    assert_empty @org.reload.pinned_repositories,
      "expected repo transfer to delete pinned repository"
  end

  test "converts org-owned project cards associated with public repository issues to note cards linking to the new issue URL" do
    org_1 = create(:organization, admin: @user)
    org_2 = create(:organization, admin: @user)
    repo = create(:repository, owner: org_1)
    org_project = create(:project, owner: org_1)
    org_column = create(:project_column, project: org_project)
    repo_project = create(:project, owner: repo)

    pending_issue = create(:issue, repository: repo)
    pending_org_card = create(:pending_project_card, content: pending_issue, project: org_project)
    org_issue = create(:issue, repository: repo)
    org_card = create(:project_card, content: org_issue, project: org_project)
    repo_issue = create(:issue, repository: repo)
    repo_card = create(:project_card, content: repo_issue, project: repo_project)

    repo.transfer_ownership_to(org_2, actor: @user)

    pending_issue.reload
    pending_org_card.reload
    org_issue.reload
    org_card.reload
    repo_issue.reload
    repo_card.reload

    assert_nil pending_org_card.content
    assert_equal pending_issue.url, pending_org_card.note
    assert_nil org_card.content
    assert_equal org_issue.url, org_card.note
    assert_equal repo_issue, repo_card.content
  end

  test "deletes org-owned project cards associated with private repository issues" do
    org_1 = create(:organization, admin: @user)
    org_2 = create(:organization, admin: @user)
    repo = create(:private_repository, owner: org_1)
    org_project = create(:project, owner: org_1)
    org_column = create(:project_column, project: org_project)
    repo_project = create(:project, owner: repo)

    note_card = create(:project_card, note: "a note", column: org_column)
    pending_issue = create(:issue, repository: repo)
    pending_org_card = create(:pending_project_card, content: pending_issue, project: org_project)
    org_issue = create(:issue, repository: repo)
    org_card = create(:project_card, content: org_issue, project: org_project)
    repo_issue = create(:issue, repository: repo)
    repo_card = create(:project_card, content: repo_issue, project: repo_project)

    repo.transfer_ownership_to(org_2, actor: @user)

    repo_issue.reload
    repo_card.reload

    assert_same_elements [note_card], org_project.cards
    assert_equal repo_issue, repo_card.content
  end

  test "does not delete org-owned project cards associated with private repository issues if the project is being migrated to the same target org" do
    origin = create(:organization, admin: @user)
    target = create(:organization, admin: @user)
    repo = create(:private_repository, owner: origin)
    org_project = create(:project, owner: origin)
    repo_issue = create(:issue, repository: repo)
    repo_issue_card = create(:project_card, content: repo_issue, project: org_project)
    move_work = create(:move_work, :started, origin: origin, target: target, user: @user)
    create(:move_work_item, resource: org_project, move_work: move_work)

    repo.transfer_ownership_to(target, actor: @user)

    assert_same_elements [repo_issue_card], org_project.cards
  end

  test "destroys project repository links" do
    GitHub.context.push(actor_id: @user.id)

    org_1 = create(:organization, admin: @user)
    org_2 = create(:organization, admin: @user)
    repo = create(:private_repository, owner: org_1)
    project = create(:project, owner: org_1)
    link = project.link_repository(repo, @user)

    repo.transfer_ownership_to(org_2, actor: @user)

    assert_nil ProjectRepositoryLink.find_by(id: link.id)
  end

  test "updates search index if repository has listed actions" do
    org_1 = create(:organization, admin: @user)
    org_2 = create(:organization, admin: @user)
    repo = create(:repository, owner: org_1)
    action = create(:repository_action, :listed, repository: repo)

    assert repo.listed_action.present?
    Timecop.freeze do
      timestamp = Timestamp.from_time(Time.now)
      guid = AddToSearchIndexJob.guid("repository_action", action.id)

      assert_enqueued_with job: AddToSearchIndexJob, args: ["repository_action", action.id, { "submitted_at" => timestamp, "guid" => guid }] do
        repo.transfer_ownership_to(org_2, actor: @user)
      end
    end
  end

  test "invalid when transferring would conflict with retired namespace" do
    retired_login = "yae-miko"
    retired_name  = "ei"
    create(:retired_namespace, owner: nil, owner_login: retired_login, name: retired_name)
    org = create(:organization, login: retired_login, admin: @user)
    repo = create(:repository, owner: @user, name: retired_name)

    transfer = build(:repository_transfer, repository: repo, requester: @user, target: org)
    refute_predicate transfer, :valid?
    errors = ["Repository name #{retired_login}/#{retired_name} has been retired and cannot be reused"]
    assert_equal errors, transfer.errors.full_messages
  end

  test "valid when transferring would conflict with retired namespace if namespace is claimable by target" do
    retired_login = "yae-miko"
    retired_name  = "ei"
    org = create(:organization, login: retired_login, admin: @user)
    create(:retired_namespace, owner: org, name: retired_name)
    repo = create(:repository, owner: @user, name: retired_name)

    transfer = build(:repository_transfer, repository: repo, requester: @user, target: org)
    assert_predicate transfer, :valid?
  end

  context "when repo is associated with org level discussions" do
    test "destroys record if repository set" do
      org_discussion_config = create(:organization_discussion_config)
      refute_nil org_discussion_config.repository_id

      repo = org_discussion_config.repository

      assert_difference("OrganizationDiscussionConfig.count", -1) do
        repo.transfer_ownership_to(@org, actor: repo.owner)
      end
    end
  end
end

class RepositoryTransferEnterpriseManagedUserTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @emu_1 = create :emu
    @emu_business = @emu_1.enterprise_managed_business
    @emu_2 = create :emu, business: @emu_business
    @emu_user_repo = create(:private_repository, owner: @emu_1)
    @emu_org = create :organization, business: @emu_business, admin: @emu_1
    @emu_org_repo = create(:private_repository, owner: @emu_org)
    @emu_org_2 = create :organization, business: @emu_business, admin: @emu_1

    @emu_diff_biz = create :emu
    @emu_business_2 = @emu_diff_biz.enterprise_managed_business
    @emu_org_diff_biz = create :organization, business: @emu_business_2, admin: @emu_diff_biz

    @dotcom_user = create :user
    @dotom_user_repo = create(:private_repository, owner: @dotcom_user)
    @dotcom_org = create :organization
    @dotcom_org_repo = create(:private_repository, owner: @dotcom_org)
  end

  context ":valid_emu_context" do
    context "user owned repos" do
      test "emu user owned repo can't transfer to dotcom user" do
        xfer = RepositoryTransfer.new(
          repository: @emu_user_repo,
          requester: @emu_1,
          target: @dotcom_user
        )

        refute_predicate xfer, :valid?
        assert_equal [RepositoryTransfer::CANNOT_TRANSFER_FROM_EMU_REASON], xfer.errors.full_messages
      end

      test "emu user owned repo can't transfer to dotcom org" do
        xfer = RepositoryTransfer.new(
          repository: @emu_user_repo,
          requester: @emu_1,
          target: @dotcom_org
        )

        refute_predicate xfer, :valid?
        assert_includes xfer.errors.full_messages, RepositoryTransfer::CANNOT_TRANSFER_FROM_EMU_REASON
      end

      test "emu user owned repo can't transfer to emu user from other business" do
        xfer = RepositoryTransfer.new(
          repository: @emu_user_repo,
          requester: @emu_1,
          target: @emu_diff_biz
        )

        refute_predicate xfer, :valid?
        assert_equal [RepositoryTransfer::CANNOT_TRANSFER_FROM_EMU_REASON], xfer.errors.full_messages
      end

      test "emu user owned repo can't transfer to emu org from other business" do
        xfer = RepositoryTransfer.new(
          repository: @emu_user_repo,
          requester: @emu_1,
          target: @emu_org_diff_biz
        )

        refute_predicate xfer, :valid?
        assert_includes xfer.errors.full_messages, RepositoryTransfer::CANNOT_TRANSFER_FROM_EMU_REASON
      end

      test "dotcom user owned repo can't transfer to emu user" do
        xfer = RepositoryTransfer.new(
          repository: @dotom_user_repo,
          requester: @dotcom_user,
          target: @emu_1
        )

        refute_predicate xfer, :valid?
        assert_equal [RepositoryTransfer::CANNOT_TRANSFER_TO_EMU_REASON + " '#{@emu_1.login}'"], xfer.errors.full_messages
      end

      test "dotcom user owned repo can't transfer to emu org" do
        xfer = RepositoryTransfer.new(
          repository: @dotom_user_repo,
          requester: @dotcom_user,
          target: @emu_org
        )

        refute_predicate xfer, :valid?
        assert_includes xfer.errors.full_messages, RepositoryTransfer::CANNOT_TRANSFER_TO_EMU_REASON + " '#{@emu_org.login}'"
      end

      test "emu user owned repo can transfer to other emu user in same business" do
        xfer = RepositoryTransfer.new(
          repository: @emu_user_repo,
          requester: @emu_1,
          target: @emu_2
        )

        assert_predicate xfer, :valid?
      end

      test "emu user owned repo can transfer to emu org in same business" do
        xfer = RepositoryTransfer.new(
          repository: @emu_user_repo,
          requester: @emu_1,
          target: @emu_org
        )

        assert_predicate xfer, :valid?
      end
    end

    context "org owned repos" do
      test "emu org owned repo can't transfer to dotcom org" do
        xfer = RepositoryTransfer.new(
          repository: @emu_org_repo,
          requester: @emu_1,
          target: @dotcom_org
        )

        refute_predicate xfer, :valid?
        assert_includes xfer.errors.full_messages, RepositoryTransfer::CANNOT_TRANSFER_FROM_EMU_REASON
      end

      test "emu org owned repo can't transfer to dotcom user" do
        xfer = RepositoryTransfer.new(
          repository: @emu_org_repo,
          requester: @emu_1,
          target: @dotcom_user
        )

        refute_predicate xfer, :valid?
        assert_includes xfer.errors.full_messages, RepositoryTransfer::CANNOT_TRANSFER_FROM_EMU_REASON
      end

      test "emu org owned repo can't transfer to emu org from other business" do
        xfer = RepositoryTransfer.new(
          repository: @emu_org_repo,
          requester: @emu_1,
          target: @emu_org_diff_biz
        )

        refute_predicate xfer, :valid?
        assert_includes xfer.errors.full_messages, RepositoryTransfer::CANNOT_TRANSFER_FROM_EMU_REASON
      end

      test "emu org owned repo can't transfer to emu user from other business" do
        xfer = RepositoryTransfer.new(
          repository: @emu_org_repo,
          requester: @emu_1,
          target: @emu_diff_biz
        )

        refute_predicate xfer, :valid?
        assert_includes xfer.errors.full_messages, RepositoryTransfer::CANNOT_TRANSFER_FROM_EMU_REASON
      end

      test "dotcom org owned repo can't transfer to emu org" do
        xfer = RepositoryTransfer.new(
          repository: @dotcom_org_repo,
          requester: @dotcom_user,
          target: @emu_org
        )

        refute_predicate xfer, :valid?
        assert_includes xfer.errors.full_messages, RepositoryTransfer::CANNOT_TRANSFER_TO_EMU_REASON + " '#{@emu_org.login}'"
      end

      test "dotcom org owned repo can't transfer to emu user" do
        xfer = RepositoryTransfer.new(
          repository: @dotcom_org_repo,
          requester: @dotcom_user,
          target: @emu_1
        )

        refute_predicate xfer, :valid?
        assert_includes xfer.errors.full_messages, RepositoryTransfer::CANNOT_TRANSFER_TO_EMU_REASON + " '#{@emu_1.login}'"
      end

      test "emu org owned repo can transfer to emu user in same business" do
        xfer = RepositoryTransfer.new(
          repository: @emu_org_repo,
          requester: @emu_1,
          target: @emu_1
        )

        assert_predicate xfer, :valid?
      end

      test "emu org owned repo can transfer to other emu org in same business" do
        xfer = RepositoryTransfer.new(
          repository: @emu_org_repo,
          requester: @emu_1,
          target: @emu_org_2
        )

        assert_predicate xfer, :valid?
      end
    end
  end
end unless GitHub.single_business_environment?
