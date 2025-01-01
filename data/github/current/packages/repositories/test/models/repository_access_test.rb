# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryAccessTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @owner = create(:user, plan: GitHub::Plan.find!("medium"))
    @staff = create(:staff_admin_user)
    @forker = create(:user)
    @forker2 = create(:user)
    @repo = create :repository, parent: nil, owner: @owner
    @priv = create :private_repository, owner: @owner
    @fork = create :repository, parent: @repo, owner: @forker
    @fork2 = create :repository, parent: @repo, owner: @forker2

    setup_staff_user
  end

  setup do
    ActionMailer::Base.deliveries.clear
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
    disable_feature_flag(:darkship_dmca_takedown_skip_for_perfomance_reason)
  end

  teardown do
    GitRepositoryBlock.expire_country_block_cache
  end

  def access(repo)
    repo.reload.access
  end

  def dmca_url
    "https://github.com/github/dmca/blob/master/2011/2011-01-27-sony.markdown"
  end

  def country_block_url
    "https://github.com/github/nation-state-blocks/blob/master/2011-01-27-russia.markdown"
  end

  test "new repo is enabled by default" do
    assert access(@repo).enabled?
    assert_nil access(@repo).disabled_at
    assert_nil access(@repo).disabling_reason
    assert_nil access(@repo).disabler
  end

  test "disables entire network when disabling source repo" do
    StaffNote.expects(:create).never
    access(@repo).disable("size", @staff)
    refute access(@repo).enabled?
    refute access(@fork).enabled?
    refute access(@fork2).enabled?
  end

  test "leaves rest of network untouched when disabling a fork" do
    access(@fork2).disable("size", @staff)
    refute access(@fork2).enabled?
    assert access(@repo).enabled?
    assert access(@fork).enabled?
  end

  test "enables entire network when restoring source repo access" do
    access(@repo).disable("size", @staff)
    access(@repo).enable(@staff)
    assert access(@repo).enabled?
    assert access(@fork).enabled?
    assert access(@fork2).enabled?
  end

  test "leaves rest of network untouched when restoring fork access" do
    access(@repo).disable("size", @staff)
    access(@fork).enable(@staff)
    assert access(@fork).enabled?
    refute access(@repo).enabled?
    refute access(@fork2).enabled?
  end

  test "failing to disable one fork in a transaction stops the parent" do
    @fork.update_attribute :owner_id, 0 # make the fork invalid so that updating its attributes will fail

    successes = [@fork2.id]
    failures = [@fork.id, @repo.id]

    Failbot.expects(:report).with(instance_of(GitRepositoryAccess::RepoDisableError))
    Failbot.expects(:report).with(instance_of(GitRepositoryAccess::RepoNetworkDisableError), {
      "gh.repo.parent.id": @repo.id,
      "gh.repo.disable.success_ids": successes,
      "gh.repo.disable.failure_ids": failures,
    })

    actual = access(@repo).disable("size", @staff)

    assert_same_elements successes, actual[:successes].map(&:id)
    assert_same_elements failures, actual[:failures].map(&:id)

    assert access(@repo).enabled?
    assert access(@fork).enabled?
    assert access(@fork2).disabled?
  end

  test "enables in a transaction so that failure to enable one repo stops the rest" do
    access(@repo).disable("size", @staff)
    @fork.update_attribute :owner_id, 0 # make the fork invalid so that updating its attributes will fail

    refute access(@repo).enable(@staff)

    assert access(@repo).disabled?
    assert access(@fork).disabled?
    assert access(@fork2).disabled?
  end

  test "emails are sent only for successfully disabled repos" do
    @fork.update_attribute :owner_id, 0 # make the fork invalid so that updating its attributes will fail

    actual = access(@repo).disable("size", @staff)
    assert_equal 1, actual[:successes].length
    assert_equal 2, actual[:failures].length

    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  test "sends emails to repo owner and fork owners when disabling source repo" do
    assert_performed_email(mailer: "RepositoryMailer", action: "size_disabled_notice", args: [@fork, nil, { template: nil }]) do
      assert_performed_email(mailer: "RepositoryMailer", action: "size_disabled_notice", args: [@fork2, nil, { template: nil }]) do
        assert_performed_email(mailer: "RepositoryMailer", action: "size_disabled_notice", args: [@repo, nil, { template: nil }]) do
          access(@repo).disable("size", @staff)
          assert_equal 3, ActionMailer::Base.deliveries.size

          mail = ActionMailer::Base.deliveries.find { |m| m.bcc.include?(@fork.owner.email) }
          refute_nil mail
          assert_match /Access to the #{@fork.name_with_owner}/, mail.body.to_s

          mail = ActionMailer::Base.deliveries.find { |m| m.bcc.include?(@fork2.owner.email) }
          refute_nil mail
          assert_match /Access to the #{@fork2.name_with_owner}/, mail.body.to_s

          mail = ActionMailer::Base.deliveries.find { |m| m.bcc.include?(@repo.owner.email) }
          refute_nil mail
          assert_match /Access to the #{@repo.name_with_owner}/, mail.body.to_s
        end
      end
    end
  end

  test "only sends an email to repo owner when disabling source repo with notify_fork_owners: false" do
    assert_performed_email(mailer: "RepositoryMailer", action: "size_disabled_notice", args: [@repo, nil, { template: nil }]) do
      access(@repo).disable("size", @staff, notify_fork_owners: false)
      mail = ActionMailer::Base.deliveries.find { |m| m.bcc.include?(@repo.owner.email) }
      refute_nil mail
      assert_match /Access to the #{@repo.name_with_owner}/, mail.body.to_s
    end
  end

  test "only sends email to fork owner when disabling a fork" do
    assert_performed_email(mailer: "RepositoryMailer", action: "size_disabled_notice", args: [@fork, nil, { template: nil }]) do
      access(@fork).disable("size", @staff)
      mail = ActionMailer::Base.deliveries.find { |m| m.bcc.include?(@fork.owner.email) }
      refute_nil mail
      assert_includes mail.bcc, @fork.owner.email
    end
  end

  test "records when access was disabled" do
    access(@repo).disable("size", @staff)
    assert_respond_to access(@repo).disabled_at, :to_time
  end

  test "removing a repo due to size increments stats" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    assert_equal 0, GitHub.dogstats.increments("repo.disable", tags: ["disable_reason:size"]).count
    access(@repo).disable("size", @staff)
    assert_equal 1, GitHub.dogstats.increments("repo.disable", tags: ["disable_reason:size"]).count
  end

  test "enable a repo taken down for size violation increments stats" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    access(@repo).disable("size", @staff)
    assert_equal 0, GitHub.dogstats.increments("repo.enable", tags: ["disable_reason:size"]).count
    access(@repo).enable(@staff)
    assert_equal 1, GitHub.dogstats.increments("repo.enable", tags: ["disable_reason:size"]).count
  end


  test "records reason for disabling the repo" do
    access(@repo).disable("size", @staff)
    assert_equal "size", access(@repo).disabling_reason
  end

  test "records the user disabling the repo" do
    access(@repo).disable("size", @staff)
    assert_equal @staff, access(@repo).disabler
  end

  test "refuses to disable access for invalid reasons" do
    e = assert_raises(GitRepositoryAccess::Error) do
      access(@repo).disable(nil, @staff)
    end
    assert_equal "invalid reason: nil", e.message

    e = assert_raises(GitRepositoryAccess::Error) do
      access(@repo).disable("", @staff)
    end
    assert_equal "invalid reason: \"\"", e.message

    e = assert_raises(GitRepositoryAccess::Error) do
      access(@repo).disable("boom", @staff)
    end
    assert_equal "invalid reason: \"boom\"", e.message
  end

  test "refuses to disable access to a repository that's already disabled" do
    access(@repo).disable("size", @staff)
    e = assert_raises(GitRepositoryAccess::Error) do
      access(@repo).disable("size", @staff)
    end
    assert_equal "repo already disabled", e.message
  end

  test "refuses to re-enable access to a repository that's not disabled" do
    e = assert_raises(GitRepositoryAccess::Error) do
      access(@repo).enable(@staff)
    end
    assert_equal "repo not disabled", e.message
  end

  context "#dmca_takedown", skip_enterprise: true do
    test "dmca takedown disables access" do
      refute access(@repo).disabled?
      access(@repo).dmca_takedown(@staff, dmca_url)
      assert access(@repo).disabled?
    end

    test "dmca takedown reports stats" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      assert_equal 0, GitHub.dogstats.increments("repo.disable", tags: ["disable_reason:dmca"]).count
      access(@repo).dmca_takedown(@staff, dmca_url)
      assert_equal 1, GitHub.dogstats.increments("repo.disable", tags: ["disable_reason:dmca"]).count
    end

    test "dmca takedown disables forks" do
      refute access(@fork).disabled?
      access(@repo).dmca_takedown(@staff, dmca_url)
      assert access(@fork).disabled?
      assert access(@fork2).disabled?
    end

    test "dmca takedown records reason" do
      assert_nil access(@repo).disabling_reason
      access(@repo).dmca_takedown(@staff, dmca_url)
      assert_equal "dmca", access(@repo).disabling_reason
    end

    test "dmca takedown records url of dmca takedown notice" do
      assert_nil access(@repo).dmca_url
      access(@repo).dmca_takedown(@staff, dmca_url)
      assert_equal dmca_url, access(@repo).dmca_url
    end

    test "dmca takedown emails notice to repo owner and fork owners" do
      assert_performed_email(mailer: "RepositoryMailer", action: "dmca_takedown_notice", args: [@fork, dmca_url]) do
        assert_performed_email(mailer: "RepositoryMailer", action: "dmca_takedown_notice", args: [@fork2, dmca_url]) do
          assert_performed_email(mailer: "RepositoryMailer", action: "dmca_takedown_notice", args: [@repo, dmca_url]) do
            access(@repo).dmca_takedown(@staff, dmca_url)
            assert_equal 3, ActionMailer::Base.deliveries.size

            mail = ActionMailer::Base.deliveries.find { |m| m.bcc.include?(@fork.owner.email) }
            refute_nil mail
            assert_equal "[GitHub] DMCA takedown notice for #{@fork.name_with_owner}", mail.subject
            assert mail.body.include?(dmca_url)

            mail = ActionMailer::Base.deliveries.find { |m| m.bcc.include?(@fork2.owner.email) }
            refute_nil mail
            assert_equal "[GitHub] DMCA takedown notice for #{@fork2.name_with_owner}", mail.subject
            assert mail.body.include?(dmca_url)

            mail = ActionMailer::Base.deliveries.find { |m| m.bcc.include?(@repo.owner.email) }
            refute_nil mail
            assert_equal "[GitHub] DMCA takedown notice for #{@repo.name_with_owner}", mail.subject
            assert mail.body.include?(dmca_url)
          end
        end
      end
    end

    test "dmca takedown marks repo as such" do
      refute access(@repo).dmca?
      access(@repo).dmca_takedown(@staff, dmca_url)
      assert access(@repo).dmca?
    end

    test "removes dmca takedown" do
      access(@repo).dmca_takedown(@staff, dmca_url)
      assert access(@repo).disabled?

      access(@repo).enable(@staff)
      refute access(@repo).disabled?
    end

    test "removing a dmca takedown increments stats" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      access(@repo).dmca_takedown(@staff, dmca_url)
      assert_equal 0, GitHub.dogstats.increments("repo.enable", tags: ["disable_reason:dmca"]).count
      access(@repo).enable(@staff)
      assert_equal 1, GitHub.dogstats.increments("repo.enable", tags: ["disable_reason:dmca"]).count
    end

    test "removes dmca takedown from forks of reenabled parent" do
      access(@repo).dmca_takedown(@staff, dmca_url)
      assert access(@fork).disabled?
      assert access(@fork2).disabled?

      access(@repo).enable(@staff)
      refute access(@fork).disabled?
      refute access(@fork2).disabled?
    end

    test "forks are no longer DMCA'd after parent is reenabled" do
      access(@repo).dmca_takedown(@staff, dmca_url)
      assert access(@fork).dmca?
      assert access(@fork2).dmca?

      access(@repo).enable(@staff)
      refute access(@fork).dmca?
      refute access(@fork2).dmca?
    end

    test "can dmca takedown private repo" do
      assert access(@priv).dmca_takedown(@staff, dmca_url)
      assert access(@priv).disabled?
    end

    test "refuses to dmca takedown with invalid url" do
      refute access(@repo).dmca_takedown(@staff, "url")
      refute access(@repo).dmca?
    end

    test "allows takedowns for already-disabled repos" do
      access(@repo).disable("size", @staff)
      assert access(@repo).disabled?

      access(@repo).dmca_takedown(@staff, dmca_url)
      assert access(@repo).dmca?
    end
  end

  context "#country_block", skip_enterprise: true do
    test "country block records block url" do
      refute access(@repo).disabled?
      access(@repo).country_block(@staff, GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST, country_block_url, "Reason for country block")
      assert_equal GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST, access(@repo).country_block?("RU")
      refute access(@repo).country_block?("NL")
    end

    test "country block records reason" do
      access(@repo).country_block(@staff, GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST, country_block_url, "Reason for country block")
      @repo.reload
      expected = { GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST => country_block_url }
      assert_equal expected, @repo.country_blocks
      assert_equal country_block_url, access(@repo).country_block_url("RU")
    end

    test "country blocks are cached" do
      access(@repo).country_block(@staff, GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST, country_block_url, "Reason for country block")
      repo = create(:repository)
      assert @repo.access.country_block?("RU")

      assert_query_count(0) do
        repo.access.country_block?("RU")
      end
    end

    test "country blocks cache expires" do
      access(@repo).country_block(@staff, GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST, country_block_url, "Reason for country block")
      assert @repo.access.country_block?("RU")

      assert_query_count(0) do
        assert @repo.access.country_block?("RU")
      end

      Timecop.freeze(Time.zone.now + GitRepositoryBlock::COUNTRY_BLOCK_TTL + 5.minutes) do
        assert_query_count(1) do
          @repo.access.country_block?("RU")
        end
      end
    end

    test "GitRepositoryBlock.expire_country_block_cache reloads the blocks from disk" do
      access(@repo).country_block(@staff, GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST, country_block_url, "Reason for country block")
      assert @repo.access.country_block?("RU")

      assert_query_count(0) do
        refute_empty GitRepositoryBlock.all_country_blocks
      end

      GitRepositoryBlock.expire_country_block_cache

      assert_query_count(1) do
        refute_empty GitRepositoryBlock.all_country_blocks
      end
    end

    test "country block emails notice to owner" do
      type = GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST
      args = [
          @repo,
          type,
          country_block_url,
      ]
      assert_performed_email(mailer: "RepositoryMailer", action: "country_block_notice", args: args) do
        access(@repo).country_block(@staff, type, country_block_url, "Reason for country block")
        mail = ActionMailer::Base.deliveries.find { |m| m.bcc.include?(@repo.owner.email) }
        refute_nil mail
        assert_equal "[GitHub] Repository blocked in certain countries", mail.subject
        assert mail.body.include?(country_block_url)
      end
    end

    test "removes country block and only that one block" do
      access(@repo).country_block(@staff, GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST, country_block_url, "Reason for country block")
      access(@repo).country_block(@staff, GitRepositoryBlock::CHINESE_INTERNET_BLOCKLIST, country_block_url, "Reason for country block")
      assert access(@repo).country_block?("RU")
      assert access(@repo).country_block?("CN")

      access(@repo).remove_country_block(@staff, GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST)
      refute access(@repo).country_block?("RU")
      assert access(@repo).country_block?("CN")
    end

    test "refuses to country block private repo" do
      refute access(@priv).country_block(@staff, GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST, country_block_url, "Reason for country block")
      refute access(@repo).country_block?("RU")
    end

    test "publishes audit log events" do
      # Base properties shared by all events
      base_event = {
        actor: User.staff_user.to_s,
        actor_id: User.staff_user.id,
        repo: @repo.name_with_owner,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        user: @repo.owner.login,
        user_id: @repo.owner_id,
      }
      if GitHub.guard_audit_log_staff_actor?
        base_event[:staff_actor] = @staff.login
        base_event[:staff_actor_id] = @staff.id
      end

      # Subscribe to events we care about
      block_events = subscribe "staff.country_block"
      unblock_events = subscribe "staff.country_unblock"

      # Apply a country block
      access(@repo).country_block(@staff, GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST, country_block_url, "Because it's bad stuff")

      # Make sure the country block published an audit log event
      assert event = block_events.pop, "a staff.country_block event was expected"
      assert_equal "staff.country_block", event.name
      assert_equal(base_event.merge({
        block: GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST,
        reason: "Because it's bad stuff",
      }), event.payload)
      assert_nil block_events.pop, "no more staff.country_block events expected"

      # Remove the country block
      access(@repo).remove_country_block(@staff, GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST)

      # Make sure the country block removal published an audit log event
      assert event = unblock_events.pop, "a staff.country_unblock event was expected"
      assert_equal "staff.country_unblock", event.name
      assert_equal(base_event.merge({
        block: GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST,
      }), event.payload)
      assert_nil unblock_events.pop, "no more staff.country_unblock events expected"
    end

    test "publishes hydro events" do
      freeze_time do
        # Apply a country block
        access(@repo).country_block(@staff, GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST, country_block_url, "Because it's bad stuff")

        # Make sure the country block published a hydro event
        assert_hydro_published({
          repository: Hydro::EntitySerializer.repository(@repo),
          actor: Hydro::EntitySerializer.user(@staff),
          blocked_at: Time.now,
          type: GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST.upcase.to_s,
          country_codes: ["RU"],
          country_names: ["Russia"],
          details: "Because it's bad stuff",
          public_block_notice_url: country_block_url,
        }, schema: "github.v1.RepositoryCountryBlocked")

        # Remove the country block
        access(@repo).remove_country_block(@staff, GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST)

        # Make sure the country block removal published a hydro event
        assert_hydro_published({
          repository: Hydro::EntitySerializer.repository(@repo),
          actor: Hydro::EntitySerializer.user(@staff),
          unblocked_at: Time.now,
          type: GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST.upcase.to_s,
          country_codes: ["RU"],
          country_names: ["Russia"],
        }, schema: "github.v1.RepositoryCountryUnblocked")
      end
    end

    test "publishes ModerationAction for repository.country_block" do
      access(@repo).country_block(
        @staff,
        GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST,
        country_block_url,
        "it's bad stuff!",
        tos_reason: "VIOLENT_CONTENT",
        content_formats: %w[TEXT IMAGE],
        source: "USER_REPORT"
      )
      assert_hydro_published({
        action: "repository.country_blocked",
        actor: Hydro::EntitySerializer.user(@staff),
        is_test: false,
        content_moderation: {
          global_relay_id: @repo.global_relay_id,
          content_type: "repository",
          content: "#{GitHub.url}/#{@repo.name_with_display_owner}",
          content_created_at: @repo.created_at,
          content_updated_at: @repo.updated_at,
          end_timestamp: nil,
          moderation_types: [:DISABLED],
          formats: [:TEXT, :IMAGE]
        },
        countries: ["RU"],
        reason: :REASON_UNKNOWN,
        tos_reason: :VIOLENT_CONTENT,
        source: :USER_REPORT
      }, schema: "github.moderation.v0.ModerationAction")
    end

    test "publishes ModerationAction for a test repository.country_block action" do
      @staff.update!(email: "mona@github.com")
      test_user = create(:user, email: "mona+evil@github.com")
      @repo.update_attribute(:owner, test_user)
      access(@repo).country_block(
        @staff,
        GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST,
        country_block_url,
        "it's bad stuff!",
        tos_reason: "DISCRIMINATORY_CONTENT",
        content_formats: ["TEXT"],
        source: "DSA_REPORT"
      )
      assert_hydro_published({
        action: "repository.country_blocked",
        actor: Hydro::EntitySerializer.user(@staff),
        is_test: true,
        content_moderation: {
          global_relay_id: @repo.global_relay_id,
          content_type: "repository",
          content: "#{GitHub.url}/#{@repo.name_with_display_owner}",
          content_created_at: @repo.created_at,
          content_updated_at: @repo.updated_at,
          end_timestamp: nil,
          moderation_types: [:DISABLED],
          formats: [:TEXT]
        },
        countries: ["RU"],
        reason: :REASON_UNKNOWN,
        tos_reason: :DISCRIMINATORY_CONTENT,
        source: :DSA_REPORT
      }, schema: "github.moderation.v0.ModerationAction")
    end
  end

  test "instruments staff.disable_repo event" do
    events = subscribe "staff.disable_repo"
    if GitHub.guard_audit_log_staff_actor?
      expected_payload = {
        staff_actor: @staff.login,
        staff_actor_id: @staff.id,
        actor: User.staff_user.to_s,
        actor_id: User.staff_user.id,
        reason: "size",
        repo: @repo.name_with_owner,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        user: @repo.owner.login,
        user_id: @repo.owner_id,
      }
    else
      expected_payload = {
        actor: @staff.login,
        actor_id: @staff.id,
        reason: "size",
        repo: @repo.name_with_owner,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        user: @repo.owner.login,
        user_id: @repo.owner_id,
      }
    end

    access(@repo).disable("size", @staff)

    assert event = events.pop, "an event was expected"
    assert_equal "staff.disable_repo", event.name
    assert_equal expected_payload, event.payload
    events.pop # The bottom 2 events are the forks being disabled
    events.pop
    assert_nil events.pop, "an event was not expected"
  end

  test "publishes github.v1.RepositoryDisabled event" do
    freeze_time do
      access(@repo).disable("size", @staff)
      assert_hydro_published({
        repository: Hydro::EntitySerializer.repository(@repo),
        actor: Hydro::EntitySerializer.user(@staff),
        disabled_at: Time.now,
        reason: "size",
        details: "",
        dmca_takedown_url: "",
      }, schema: "github.v1.RepositoryDisabled")
    end
  end

  test "publishes ModerationAction event for repository.disable", skip_enterprise: true do
    access(@repo).disable(
      "private_information",
      @staff,
      content_formats: ["TEXT"],
      source: "USER_REPORT",
      tos_reason: "IMPERSONATION"
    )
    assert_hydro_published({
      action: "repository.disabled",
      actor: Hydro::EntitySerializer.user(@staff),
      is_test: false,
      content_moderation: {
        global_relay_id: @repo.global_relay_id,
        content_type: "repository",
        content: "#{GitHub.url}/#{@repo.name_with_display_owner}",
        content_created_at: @repo.created_at,
        content_updated_at: @repo.updated_at,
        end_timestamp: nil,
        moderation_types: [:DISABLED],
        formats: [:TEXT]
      },
      countries: nil,
      reason: :REASON_UNKNOWN,
      tos_reason: :IMPERSONATION,
      source: :USER_REPORT
    }, schema: "github.moderation.v0.ModerationAction")
  end

  test "publishes RepositoryDisabled event but no ModerationAction when dsa_required set to false" do
    freeze_time do
      access(@fork).disable("size", @staff, dsa_required: false)
      assert_hydro_published({
        repository: Hydro::EntitySerializer.repository(@fork),
        actor: Hydro::EntitySerializer.user(@staff),
        disabled_at: Time.now,
        reason: "size",
        details: "",
        dmca_takedown_url: "",
      }, schema: "github.v1.RepositoryDisabled")
    end
    assert_hydro_messages count: 0, schema: "github.moderation.v0.ModerationAction"
    assert_hydro_messages count: 1, schema: "github.v1.RepositoryDisabled"
  end

  test "publishes ModerationAction event for repository.disable with supplied content_formats, tos_reason", skip_enterprise: true do
    access(@repo).disable(
      "tos",
      @staff,
      content_formats: %w[TEXT IMAGE],
      tos_reason: "DISINFORMATION",
      source: "SCAN_DETECTION"
    )
    assert_hydro_published({
      action: "repository.disabled",
      actor: Hydro::EntitySerializer.user(@staff),
      is_test: false,
      content_moderation: {
        global_relay_id: @repo.global_relay_id,
        content_type: "repository",
        content: "#{GitHub.url}/#{@repo.name_with_display_owner}",
        content_created_at: @repo.created_at,
        content_updated_at: @repo.updated_at,
        end_timestamp: nil,
        moderation_types: [:DISABLED],
        formats: [:TEXT, :IMAGE]
      },
      countries: nil,
      reason: :REASON_UNKNOWN,
      tos_reason: :DISINFORMATION,
      source: :SCAN_DETECTION
    }, schema: "github.moderation.v0.ModerationAction")
  end

  test "publishes ModerationAction event for a test repository.disable action", skip_enterprise: true do
    @staff.update!(email: "mona@github.com")
    test_user = create(:user, email: "mona+evil@github.com")
    @repo.update_attribute(:owner, test_user)
    access(@repo).disable(
      "private_information",
      @staff,
      content_formats: %w[TEXT IMAGE],
      source: "STAFF_DETECTION",
      tos_reason: "MISUSE_OF_PII"
    )
    assert_hydro_published({
      action: "repository.disabled",
      actor: Hydro::EntitySerializer.user(@staff),
      is_test: true,
      content_moderation: {
        global_relay_id: @repo.global_relay_id,
        content_type: "repository",
        content: "#{GitHub.url}/#{@repo.name_with_display_owner}",
        content_created_at: @repo.created_at,
        content_updated_at: @repo.updated_at,
        end_timestamp: nil,
        moderation_types: [:DISABLED],
        formats: [:TEXT, :IMAGE]
      },
      countries: nil,
      reason: :REASON_UNKNOWN,
      tos_reason: :MISUSE_OF_PII,
      source: :STAFF_DETECTION
    }, schema: "github.moderation.v0.ModerationAction")
  end

  test "instruments staff.disable_repo event with :details" do
    details = "Beep | foo_bar | http://github.com/mona"

    events = subscribe "staff.disable_repo"
    if GitHub.guard_audit_log_staff_actor?
      expected_payload = {
        staff_actor: @staff.login,
        staff_actor_id: @staff.id,
        actor: User.staff_user.to_s,
        actor_id: User.staff_user.id,
        reason: "size",
        details: details,
        repo: @repo.name_with_owner,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        user: @repo.owner.login,
        user_id: @repo.owner_id,
      }
    else
      expected_payload = {
        actor: @staff.login,
        actor_id: @staff.id,
        reason: "size",
        details: details,
        repo: @repo.name_with_owner,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        user: @repo.owner.login,
        user_id: @repo.owner_id,
      }
    end

    access(@repo).disable("size", @staff, disabling_detail: details)

    expected_event = events.find do |e|
      e.name == "staff.disable_repo" && e.payload[:repo_id] == @repo.id
    end
    assert_equal expected_payload, expected_event.payload
  end

  test "publishes ModerationAction event for DMCA repository.disable", skip_enterprise: true do
    access(@repo).disable(
      "dmca",
      @staff,
    )
    assert_hydro_published({
      action: "repository.disabled",
      actor: Hydro::EntitySerializer.user(@staff),
      is_test: false,
      content_moderation: {
        global_relay_id: @repo.global_relay_id,
        content_type: "repository",
        content: "#{GitHub.url}/#{@repo.name_with_display_owner}",
        content_created_at: @repo.created_at,
        content_updated_at: @repo.updated_at,
        end_timestamp: nil,
        moderation_types: [:DISABLED],
        formats: [:TEXT]
      },
      countries: nil,
      reason: :REASON_UNKNOWN,
      tos_reason: :TRADEMARK,
      source: :USER_REPORT
    }, schema: "github.moderation.v0.ModerationAction")
  end

  test "doesn't instrument staff.disable_repo for failed forks" do
    events = subscribe "staff.disable_repo"

    @fork.update_attribute :owner_id, 0 # make the fork invalid so that disabling will fail
    access(@repo).disable("size", @staff)

    assert_equal 1, events.size
  end

  test "instruments staff.enable_repo event" do
    events = subscribe "staff.enable_repo"
    if GitHub.guard_audit_log_staff_actor?
      expected_payload = {
        staff_actor: @staff.login,
        staff_actor_id: @staff.id,
        actor_id: User.staff_user.id,
        actor: User.staff_user.to_s,
        repo: @repo.name_with_owner,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        user: @repo.owner.login,
        user_id: @repo.owner_id,
        disable_reason: "size",
      }
    else
      expected_payload = {
        actor: @staff.login,
        actor_id: @staff.id,
        repo: @repo.name_with_owner,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        user: @repo.owner.login,
        user_id: @repo.owner_id,
        disable_reason: "size",
      }
    end

    access(@repo).disable("size", @staff)
    access(@repo).enable(@staff)

    expected_event = events.find do |e|
      e.name == "staff.enable_repo" && e.payload[:repo_id] == @repo.id
    end
    assert_equal expected_payload, expected_event.payload
  end

  test "publishes github.v1.RepositoryEnabled event" do
    freeze_time do
      access(@repo).disable("size", @staff)
      access(@repo).enable(@staff)
      assert_hydro_published({
        repository: Hydro::EntitySerializer.repository(@repo),
        actor: Hydro::EntitySerializer.user(@staff),
        enabled_at: Time.now,
      }, schema: "github.v1.RepositoryEnabled")
    end
  end

  test "doesn't instrument staff.enable_repo event when the disable fails due to transaction rollback" do
    access(@repo).disable("size", @staff)
    events = subscribe "staff.enable_repo"

    @fork.update_attribute :owner_id, 0 # make the fork invalid so that disabling will fail
    access(@repo).enable(@staff)

    assert_nil events.pop
  end

  test "abusive? returns true when repo disabled for size" do
    refute access(@repo).abusive?
    access(@repo).disable("size", @staff)
    assert access(@repo).abusive?
  end

  test "broken? returns true when the repo's network is broken" do
    refute access(@repo).broken?
    @repo.network.update_attribute :maintenance_status, "broken"
    assert access(@repo).broken?
  end

  test "broken? returns true when the repo has been marked as broken" do
    refute access(@repo).broken?
    access(@repo).mark_broken_git_repository
    assert access(@repo).broken?
  end

  if GitHub.enterprise?
    test "disabled_by_admin? returns true when repo disabled by an admin" do
      refute access(@repo).disabled_by_admin?
      access(@repo).disable("admin", @staff)
      assert access(@repo).disabled_by_admin?
    end
  else

    test "tos_violation? returns true when repo disabled for tos violation" do
      refute access(@repo).tos_violation?
      access(@repo).disable("tos", @staff)
      assert access(@repo).tos_violation?
    end

    test "trademark_violation? returns true when repo disable for trademark violation" do
      refute access(@repo).trademark_violation?
      access(@repo).disable("trademark", @staff)
      assert access(@repo).trademark_violation?
    end
  end
end
