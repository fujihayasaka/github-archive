# typed: true
# frozen_string_literal: true

require "test_helper"

class ProgrammaticAccessBotTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers

  fixtures do
    @pat = create(:user_programmatic_access)
    @user = @pat.owner
    @subject = @pat.bot
  end

  def described_class
    ProgrammaticAccessBot
  end

  context "validation" do
    test "does not require email" do
      bot = described_class.new(login: "pat-bot")
      bot.valid?

      assert_predicate bot.errors[:email], :blank?
    end

    test "does not require a password" do
      bot = described_class.new(login: "pat-bot")
      bot.valid?

      assert_predicate bot.errors[:password], :blank?
    end

    test "requires a login" do
      bot = described_class.new
      bot.valid?

      refute_predicate bot.errors[:login], :blank?
    end

    test "login must be suffixed with '[api]'" do
      bot = described_class.new(login: "pat-v2[api]")
      bot.valid?

      assert_predicate bot.errors[:login], :blank?

      bot = described_class.new(login: "pat-v2")
      bot.valid?

      assert_includes bot.errors[:login], "is not in the correct format"
    end

    test "login must be under 39 chars" do
      too_long_str = "r" * (ProgrammaticAccessBot::MAX_SLUG_LENGTH + 1)
      bot = described_class.new(login: "#{too_long_str}[api]")
      bot.valid?

      refute_predicate bot.errors[:login], :blank?
    end
  end

  if GitHub.spamminess_check_enabled?
    test "preemptively_safelist" do
      assert_predicate @subject, :hammy?
    end
  end

  test "does not need a verified email address in order to create content" do
    GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
    refute_predicate @subject, :require_email_verification?
    refute_predicate @subject, :content_creation_requires_email_verification?
  end

  context "#ability_delegate" do
    test "responds with #grant" do
      grant = make_programmatic_access_grant(
        access: @pat, repository_selection: :all, permissions: { "metadata" => :read }
      )

      @subject.grant = grant
      assert_equal grant, @subject.ability_delegate
    end

    test "returns nil if there is nothing set for #grant" do
      bot = described_class.new
      assert_nil bot.ability_delegate
    end
  end

  test "#slug returns the login minus the login suffix" do
    expected = @subject.login.gsub("\[api\]", "")
    assert_equal expected, @subject.slug
  end

  test "#display_login returns the login" do
    assert_equal @subject.login, @subject.display_login
  end

  test "#display_login_legacy returns the slug" do
    assert_equal @subject.slug, @subject.display_login_legacy
  end

  context "graphql" do
    test "it implements next_global_id" do
      refute_predicate @subject.next_global_id, :empty?
      assert_match /PABOT/, @subject.next_global_id
    end
  end
end
