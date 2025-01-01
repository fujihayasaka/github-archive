# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::ToggleFailoverTest < GitHub::TestCase
  include GitHub::Memoizer

  fixtures do
    @user = create(:user)
  end

  # These tests contain a lot of what *seems* like logically redundant behavior, disabling flags
  # and before setting their enabled percentage; we need to ensure that the enabled percentage is
  # actually dictating the result of #enabled? checks though, rather than a global enablement gate
  # (such as the one set by the TEST_ALL_FEATURES flag).

  context "redirecting" do
    test "it throws if the region has no available backups while rejecting resumes" do
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)
      # Pretend all of our regions are in one geo
      Codespaces::Locations::Region.any_instance.stubs(geo: stamp.geo)
      stamp.available_backups(user: @user).each { |backup| backup.failover }

      assert_raises Codespaces::ToggleFailover::Unavailable do
        Codespaces::ToggleFailover.call(stamp:, codespaces_repository:, redirect: true)
      end
    end

    test "it throws if the region has no available backups while rejecting creates" do
      # When failing over prod without an actor we leverage `User.ghost` to check for available backups in the command.
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)
      # Pretend all of our regions are in one geo
      Codespaces::Locations::Region.any_instance.stubs(geo: stamp.geo)
      stamp.available_backups(user: @user).each { |backup| backup.failover }

      assert_raises Codespaces::ToggleFailover::Unavailable do
        Codespaces::ToggleFailover.call(stamp:, codespaces_repository:, redirect: true)
      end
    end

    test "it allows failover of non-production regions when not given an actor" do
      # This happens for automated failover via the API where we do not have an actor at all. In that case we don't
      # want to check `User.ghost` against non-prod stamps because they lack access w/out the codespaces_developer FF.
      stamp = Codespaces::VscsServiceStamp.find(region: "CanadaCentral", vscs_target: :ppe)
      # Pretend all of our regions are in one geo
      Codespaces::Locations::Region.any_instance.stubs(geo: stamp.geo)
      stamp.available_backups(user: @user).each { |backup| backup.failover }

      assert_nothing_raised do
        Codespaces::ToggleFailover.call(stamp:, codespaces_repository:, redirect: true)
      end
    end

    test "it prevents failover of non-production regions when given an actor" do
      # The chatops use this command also but they have/provide an actor. In those cases we can expect that actor to
      # be a codespaces_developer and then validate the non-prod stamp has available backups.
      enable_feature_flag(:codespaces_developer, @user)
      stamp = Codespaces::VscsServiceStamp.find(region: "CanadaCentral", vscs_target: :ppe)
      # Pretend all of our regions are in one geo
      Codespaces::Locations::Region.any_instance.stubs(geo: stamp.geo)
      stamp.available_backups(user: @user).each { |backup| backup.failover }

      assert_raises Codespaces::ToggleFailover::Unavailable do
        Codespaces::ToggleFailover.call(stamp:, codespaces_repository:, redirect: true, actor: @user.login)
      end
    end

    test "it throws if only is provided with an invalid value and sends to Chatterbox" do
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)

      GitHub::Chatterbox.client.expects(:say!).with(
        "#codespaces-ops",
        ":red-error: Enabling regional failover for EastUs in production by automation encountered an unexpected error: `only` must specify one of create, creates, resume, resumes"
      )

      GitHub::Chatterbox.client.expects(:say!).with(
        "#codespaces-first-responder",
        ":red-error: Enabling regional failover for EastUs in production by automation encountered an unexpected error: `only` must specify one of create, creates, resume, resumes"
      )

      assert_raises ArgumentError do
        Codespaces::ToggleFailover.call(stamp:, codespaces_repository:, redirect: true, only: "invalid")
      end
    end

    test "it rejects resumes and creates by default" do
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)

      Codespaces::ToggleFailover.call(stamp:, codespaces_repository:, redirect: true)

      refute stamp.available?(user: @user)
    end

    test "it allows rejection of only creates" do
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)

      Codespaces::ToggleFailover.call(stamp:, codespaces_repository:, redirect: true, only: "create")

      assert stamp.available_for_resumes?(user: @user)
      refute stamp.available_for_creates?(user: @user)
    end

    test "it allows rejection of only resumes" do
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)

      Codespaces::ToggleFailover.call(stamp:, codespaces_repository:, redirect: true, only: "resume")

      assert stamp.available_for_creates?(user: @user)
      refute stamp.available_for_resumes?(user: @user)
    end

    test "it respects the lock and sends to Chatterbox" do
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)

      mutex = GitHub::Redis::Mutex.new("codespaces-test-lock", wait: 0.1).unlock!
      assert mutex.lock

      GitHub::Chatterbox.client.expects(:say!).with(
        "#codespaces-ops",
        ":red-error: Enabling regional failover for EastUs in production by automation failed. Lock is held, failover may already be in progress."
      )

      assert_raises Codespaces::ToggleFailover::Unavailable do
        Codespaces::ToggleFailover.call(stamp:, mutex:, codespaces_repository:, redirect: true)
      end

      assert stamp.available_for_creates?(user: @user)
      assert stamp.available_for_resumes?(user: @user)
    end

    test "it pushes the actor into the context if provided" do
      actor = "cool-codespace-eng"
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)

      Codespaces::ToggleFailover.call(stamp:, codespaces_repository:, redirect: true, actor:)

      assert_equal actor, GitHub.context[:actor]
      assert_equal actor, Audit.context[:actor]
    end

    test "it includes the percent redirected in the Chatterbox message" do
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)

      GitHub::Chatterbox.client.expects(:say!).with(
        "#codespaces-ops",
        ":fluent-globe_with_meridians: Enabling 50% regional failover for EastUs in production by automation succeeded."
      )

      GitHub::Chatterbox.client.expects(:say!).with(
        "#codespaces-first-responder",
        ":fluent-globe_with_meridians: Enabling 50% regional failover for EastUs in production by automation succeeded."
      )

      Codespaces::ToggleFailover.call(stamp:, codespaces_repository:, redirect: true, percent: 50)
    end

    test "it allows for partial redirects" do
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)

      Codespaces::ToggleFailover.call(stamp:, codespaces_repository:, redirect: true, percent: 50)

      assert_equal 50, stamp.percent_available_for_creates
      assert_equal 50, stamp.percent_available_for_resumes
    end

    test "it defaults to 100% redirects" do
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)

      Codespaces::ToggleFailover.call(stamp:, codespaces_repository:, redirect: true)

      assert_equal 0, stamp.percent_available_for_creates
      assert_equal 0, stamp.percent_available_for_resumes
    end

    test "it allows for 0% redirects to naturally be a failback instead" do
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)

      GitHub::Chatterbox.client.expects(:say!).with(
        "#codespaces-ops",
        ":fluent-globe_with_meridians: Disabling regional failover for EastUs in production by automation succeeded."
      )

      GitHub::Chatterbox.client.expects(:say!).with(
        "#codespaces-first-responder",
        ":fluent-globe_with_meridians: Disabling regional failover for EastUs in production by automation succeeded."
      )

      Codespaces::ToggleFailover.call(stamp:, codespaces_repository:, redirect: true, percent: 0)

      assert_equal 100, stamp.percent_available_for_creates
      assert_equal 100, stamp.percent_available_for_resumes
    end
  end

  context "restoring" do
    test "it restores resumes and creates and sends to Chatterbox" do
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)

      stamp.failover

      refute stamp.available_for_creates?(user: @user)
      refute stamp.available_for_resumes?(user: @user)
      GitHub::Chatterbox.client.expects(:say!).with(
        "#codespaces-ops",
        ":fluent-globe_with_meridians: Disabling regional failover for EastUs in production by automation succeeded."
      )

      GitHub::Chatterbox.client.expects(:say!).with(
        "#codespaces-first-responder",
        ":fluent-globe_with_meridians: Disabling regional failover for EastUs in production by automation succeeded."
      )

      Codespaces::ToggleFailover.call(stamp:, codespaces_repository:, redirect: false)

      assert stamp.available_for_creates?(user: @user)
      assert stamp.available_for_resumes?(user: @user)
    end

    test "it respects the `only` argument" do
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)

      stamp.failover

      Codespaces::ToggleFailover.call(stamp:, codespaces_repository:, redirect: false, only: "resume")

      refute stamp.available_for_creates?(user: @user)
      assert stamp.available_for_resumes?(user: @user)
    end

    test "it pushes the actor into the context if provided" do
      actor = "cool-codespace-eng"
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)

      stamp.failover

      Codespaces::ToggleFailover.call(stamp:, codespaces_repository:, redirect: false, actor:)

      assert_equal actor, GitHub.context[:actor]
      assert_equal actor, Audit.context[:actor]
    end

    test "it disallows for partial restores to avoid confusion between the two inverse commands" do
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)

      Codespaces::ToggleFailover.call(stamp:, codespaces_repository:, redirect: false, percent: 50)

      assert_equal 100, stamp.percent_available_for_creates
      assert_equal 100, stamp.percent_available_for_resumes
    end
  end

  memoize def codespaces_repository
    create(:repository)
  end
end
