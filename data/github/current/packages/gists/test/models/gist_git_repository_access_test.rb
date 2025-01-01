# typed: true
# frozen_string_literal: true

require "test_helper"

class GistGitRepositoryAccessTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, plan: GitHub::Plan.find!("medium"))
    @staff = create(:staff_admin_user)
    @forker = create(:user)
    @forker2 = create(:user)
    contents = [{ name: "1", value: "random content" }]
    @gist = GistHelpers.generate contents: contents, user: @owner, public: true
    @secret = GistHelpers.generate contents: contents, user: @owner, public: false
    @fork = @gist.fork @forker
    @fork2 = @gist.fork @forker2

    setup_staff_user
  end

  setup do
    ActionMailer::Base.deliveries.clear
    GitHub.flipper[:darkship_dmca_takedown_skip_for_perfomance_reason].disable
  end

  teardown do
    GitRepositoryBlock.expire_country_block_cache
  end

  def access(gist)
    gist.reload.access
  end

  def dmca_url
    "https://github.com/github/dmca/blob/master/2011/2011-01-27-sony.markdown"
  end

  def country_block_url
    "https://github.com/github/nation-state-blocks/blob/master/2011-01-27-russia.markdown"
  end

  test "new gist is enabled by default" do
    assert access(@gist).enabled?
    assert_nil access(@gist).disabled_at
    assert_nil access(@gist).disabling_reason
    assert_nil access(@gist).disabler
  end

  test "disables entire network when disabling parent gist" do
    access(@gist).disable("size", @staff)
    refute access(@gist).enabled?
    refute access(@fork).enabled?
    refute access(@fork2).enabled?
  end

  test "leaves rest of network untouched when disabling a fork" do
    access(@fork2).disable("size", @staff)
    refute access(@fork2).enabled?
    assert access(@gist).enabled?
    assert access(@fork).enabled?
  end

  test "enables entire network when restoring source gist access" do
    access(@gist).disable("size", @staff)
    access(@gist).enable(@staff)

    assert access(@gist).enabled?
    assert access(@fork).enabled?
    assert access(@fork2).enabled?
  end

  test "leaves deleted gists alone when re-enabling entire network" do
    @fork.hide

    access(@gist).disable("size", @staff)
    access(@gist).enable(@staff)

    assert access(@gist).enabled?
    refute @fork.reload.active?
    assert access(@fork2).enabled?
  end

  test "leaves rest of network untouched when restoring fork access" do
    access(@gist).disable("size", @staff)
    access(@fork).enable(@staff)
    assert access(@fork).enabled?
    refute access(@gist).enabled?
    refute access(@fork2).enabled?
  end

  test "disables outside a transaction so that failure to disable one gist does not stop the rest" do
    @fork.update_attribute :repo_name, nil # make the fork invalid so that updating its attributes will fail

    actual = access(@gist).disable("size", @staff)

    assert_same_elements [@fork2.id], actual[:successes].map(&:id)
    assert_same_elements [@fork.id, @gist.id], actual[:failures].map(&:id)

    assert access(@gist).enabled?
    assert access(@fork).enabled?
    refute access(@fork2).enabled?
  end

  test "enables in a transaction so that failure to enable one gist stops the rest" do
    access(@gist).disable("size", @staff)
    @fork.update_attribute :repo_name, nil # make the fork invalid so that updating its attributes will fail

    refute access(@gist).enable(@staff)

    assert access(@gist).disabled?
    assert access(@fork).disabled?
    assert access(@fork2).disabled?
  end

  test "records when access was disabled" do
    access(@gist).disable("size", @staff)
    assert_respond_to access(@gist).disabled_at, :to_time
  end

  test "records reason for disabling the repo" do
    access(@gist).disable("size", @staff)
    assert_equal "size", access(@gist).disabling_reason
  end

  test "records the user disabling the repo" do
    access(@gist).disable("size", @staff)
    assert_equal @staff, access(@gist).disabler
  end

  test "refuses to disable access for invalid reasons" do
    e = assert_raises(GitRepositoryAccess::Error) do
      access(@gist).disable(nil, @staff)
    end
    assert_equal "invalid reason: nil", e.message

    e = assert_raises(GitRepositoryAccess::Error) do
      access(@gist).disable("", @staff)
    end
    assert_equal "invalid reason: \"\"", e.message

    e = assert_raises(GitRepositoryAccess::Error) do
      access(@gist).disable("boom", @staff)
    end
    assert_equal "invalid reason: \"boom\"", e.message
  end

  test "refuses to disable access to a repository that's already disabled" do
    access(@gist).disable("size", @staff)
    e = assert_raises(GitRepositoryAccess::Error) do
      access(@gist).disable("size", @staff)
    end
    assert_equal "gist already disabled", e.message
  end

  test "refuses to re-enable access to a repository that's not disabled" do
    e = assert_raises(GitRepositoryAccess::Error) do
      access(@gist).enable(@staff)
    end
    assert_equal "gist not disabled", e.message
  end

  if !GitHub.enterprise?
    test "dmca takedown disables access" do
      refute access(@gist).disabled?
      perform_enqueued_jobs only: [DisableRepositoryAccessJob] do
        access(@gist).dmca_takedown(@staff, dmca_url)
      end
      assert access(@gist).disabled?
    end

    test "dmca takedown records reason" do
      assert_nil access(@gist).disabling_reason
      perform_enqueued_jobs only: [DisableRepositoryAccessJob] do
        access(@gist).dmca_takedown(@staff, dmca_url)
      end
      assert_equal "dmca", access(@gist).disabling_reason
    end

    test "dmca takedown records url of dmca takedown notice" do
      assert_nil access(@gist).dmca_url
      perform_enqueued_jobs only: [DisableRepositoryAccessJob] do
        access(@gist).dmca_takedown(@staff, dmca_url)
      end
      assert_equal dmca_url, access(@gist).dmca_url
    end

    test "dmca takedown marks gist as such" do
      refute access(@gist).dmca?
      perform_enqueued_jobs only: [DisableRepositoryAccessJob] do
        access(@gist).dmca_takedown(@staff, dmca_url)
      end
      assert access(@gist).dmca?
    end

    test "removes dmca takedown" do
      perform_enqueued_jobs only: [DisableRepositoryAccessJob] do
        access(@gist).dmca_takedown(@staff, dmca_url)
      end
      assert access(@gist).disabled?

      access(@gist).enable(@staff)
      refute access(@gist).disabled?
    end

    test "allows dmca takedown on private repo" do
      perform_enqueued_jobs only: [DisableRepositoryAccessJob] do
        assert access(@secret).dmca_takedown(@staff, dmca_url)
      end
      assert access(@secret).disabled?
    end

    test "refuses to dmca takedown with invalid url" do
      refute access(@gist).dmca_takedown(@staff, "url")
      refute access(@gist).dmca?
    end

    test "country block records block url" do
      refute access(@gist).disabled?
      access(@gist).country_block(@staff, GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST, country_block_url, "Reason for country block")
      assert_equal GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST, access(@gist).country_block?("RU")
      refute access(@gist).country_block?("NL")
    end

    test "country block records reason" do
      assert_empty @gist.country_blocks
      access(@gist).country_block(@staff, GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST, country_block_url, "Reason for country block")
      @gist.reload
      expected = { GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST => country_block_url }
      assert_equal expected, @gist.country_blocks
      assert_equal country_block_url, access(@gist).country_block_url("RU")
    end

    test "removes country block" do
      access(@gist).country_block(@staff, GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST, country_block_url, "Reason for country block")
      assert access(@gist).country_block?("RU")

      access(@gist).remove_country_block(@staff, GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST)
      refute access(@gist).country_block?("RU")
    end

    test "refuses to country block private repo" do
      refute access(@secret).country_block(@staff, GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST, country_block_url, "Reason for country block")
      refute access(@gist).country_block?("RU")
    end
  end

  test "instruments staff.disable_gist event" do
    events = subscribe "staff.disable_gist"
    if GitHub.guard_audit_log_staff_actor?
      expected_payload = {
        staff_actor: @staff.login,
        staff_actor_id: @staff.id,
        actor: User.staff_user.to_s,
        actor_id: User.staff_user.id,
        reason: "size",
        gist: @gist.name_with_owner,
        gist_id: @gist.id,
        user: @gist.owner.login,
        user_id: @gist.user_id,
      }
    else
      expected_payload = {
        actor: @staff.login,
        actor_id: @staff.id,
        reason: "size",
        gist: @gist.name_with_owner,
        gist_id: @gist.id,
        user: @gist.owner.login,
        user_id: @gist.user_id,
      }
    end

    access(@gist).disable("size", @staff)

    assert event = events.pop, "an event was expected"
    assert_equal "staff.disable_gist", event.name
    assert_equal expected_payload, event.payload
    events.pop # The bottom 2 events are the forks being disabled
    events.pop
    assert_nil events.pop, "an event was not expected"
  end

  test "doesn't instrument staff.disable_gist event when the disable fails due to transaction rollback" do
    events = subscribe "staff.disable_gist"

    @fork.update_attribute :repo_name, nil # make the fork invalid so that disabling will fail
    access(@gist).disable("size", @staff)

    assert_equal 1, events.length
  end

  test "instruments staff.enable_gist event" do
    events = subscribe "staff.enable_gist"
    if GitHub.guard_audit_log_staff_actor?
      expected_payload = {
        staff_actor: @staff.login,
        staff_actor_id: @staff.id,
        actor: User.staff_user.to_s,
        actor_id: User.staff_user.id,
        gist: @gist.name_with_owner,
        disable_reason: "size",
        gist_id: @gist.id,
        user: @gist.owner.login,
        user_id: @gist.user_id,
      }
    else
      expected_payload = {
        actor: @staff.login,
        actor_id: @staff.id,
        gist: @gist.name_with_owner,
        disable_reason: "size",
        gist_id: @gist.id,
        user: @gist.owner.login,
        user_id: @gist.user_id,
      }
    end

    access(@gist).disable("size", @staff)
    access(@gist).enable(@staff)

    events.pop # The top 2 events are the forks being enabled
    events.pop
    assert event = events.pop, "an event was expected"
    assert_equal "staff.enable_gist", event.name
    assert_equal expected_payload, event.payload
    assert_nil events.pop, "an event was not expected"
  end

  test "doesn't instrument staff.enable_gist event when the disable fails due to transaction rollback" do
    access(@gist).disable("size", @staff)
    events = subscribe "staff.enable_gist"

    @fork.update_attribute :repo_name, nil # make the fork invalid so that disabling will fail
    access(@gist).enable(@staff)

    assert_nil events.pop
  end

  test "abusive? returns true when gist disabled for size" do
    refute access(@gist).abusive?
    access(@gist).disable("size", @staff)
    assert access(@gist).abusive?
  end

  test "broken? returns true when the gist has been marked as broken" do
    refute access(@gist).broken?
    access(@gist).mark_broken_git_repository
    assert access(@gist).broken?
  end

  if GitHub.enterprise?
    test "disabled_by_admin? returns true when gist disabled by an admin" do
      refute access(@gist).disabled_by_admin?
      access(@gist).disable("admin", @staff)
      assert access(@gist).disabled_by_admin?
    end
  else

    test "tos_violation? returns true when gist disabled for tos violation" do
      refute access(@gist).tos_violation?
      access(@gist).disable("tos", @staff)
      assert access(@gist).tos_violation?
    end

  end
end
