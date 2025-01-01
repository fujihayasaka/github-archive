# typed: true
# frozen_string_literal: true

require "test_helper"

class CreatingAKeyLinkTest < GitHub::TestCase
  include HydroTestHelpers
  include AuditLog::IntegrationTestHelpers
  include BackgroundDeletesTestHelpers

  fixtures do
    @user     = create(:user)
    @repo     = create :repository, owner: @user
  end

  test "key examples <num>" do
    keylink = build(:key_link, key_prefix: "FOO", url_template: "https://example/<num>")
    assert_equal "FOO1a23v", keylink.example_key
    assert_equal "https://example/1a23v", keylink.example_url

    keylink2 = build(:key_link, key_prefix: "BAR", url_template: "https://example/<num>", is_alphanumeric: false)
    assert_equal "BAR123", keylink2.example_key
    assert_equal "https://example/123", keylink2.example_url
  end

  test "prefix with emoji rejected" do
    keylink = build(:key_link, key_prefix: "🐹")
    refute_predicate keylink, :valid?
    assert keylink.errors[:key_prefix].any?
  end

  test "key prefix uniqueness" do
    create(:key_link, owner: @repo, key_prefix: "BAR-")

    refute_predicate build(:key_link, owner: @repo, key_prefix: "bAR-"), :valid?
    refute_predicate build(:key_link, owner: @repo, key_prefix: "BAR-"), :valid?
  end


  test "key prefix length" do
    assert_predicate build(:key_link, key_prefix: "A"), :valid?
    assert_predicate build(:key_link, key_prefix: "ABCABCABCABCABCABCABCABCABCABCAB"), :valid?
    refute_predicate build(:key_link, key_prefix: ""), :valid?
    refute_predicate build(:key_link, key_prefix: "ABCABCABCABCABCABCABCABCABCABCABC"), :valid?
  end

  test "key prefix format" do
    assert_predicate build(:key_link, key_prefix: "AB"), :valid?
    assert_predicate build(:key_link, key_prefix: "A/"), :valid?
    assert_predicate build(:key_link, key_prefix: "A.-_+:/#="), :valid?
    assert_predicate build(:key_link, key_prefix: "A2B"), :valid?
    assert_predicate build(:key_link, key_prefix: "ABC"), :valid?
    refute_predicate build(:key_link, key_prefix: "1"), :valid?
    refute_predicate build(:key_link, key_prefix: "A2"), :valid?
    refute_predicate build(:key_link, key_prefix: "AB3"), :valid?
    refute_predicate build(:key_link, key_prefix: "AB1"), :valid?
    refute_predicate build(:key_link, key_prefix: "1BC"), :valid?
    refute_predicate build(:key_link, key_prefix: "(ZD)"), :valid?
    refute_predicate build(:key_link, key_prefix: "ZD%"), :valid?
  end

  test "url template format" do
    assert_predicate build(:key_link, url_template: "http://a/ABC<num>"), :valid?
    refute_predicate build(:key_link, url_template: "http://a/"), :valid?
    refute_predicate build(:key_link, url_template: "htp://a/ABC<num>"), :valid?
    refute_predicate build(:key_link, url_template: ""), :valid?
    refute_predicate build(:key_link, url_template: "javascript:alert(1)"), :valid?
    refute_predicate build(:key_link, url_template: "https://google.com/ABC<num>\"><b>hey</b>"), :valid?
    refute_predicate build(:key_link, url_template: "https://foo.com\"><script>alert()</script>/ticket?id="), :valid?
    refute_predicate build(:key_link, url_template: "https://foo.com/ alert() ticket?id="), :valid?
  end

  test "key link maximum count" do
    KeyLink.stub_const(:MAX_PER_OWNER, { Repository: 2 }) do
      2.times { create(:key_link, owner: @repo) }

      key_link = build(:key_link, owner: @repo)
      refute_predicate key_link, :valid?
      assert_includes key_link.errors[:base], "A maximum of 2 autolink references may be created per Repository"
    end
  end

  test "cannot create alphanumeric key link with matching prefix" do
    create(:key_link, owner: @repo, key_prefix: "ABC")
    create(:key_link, owner: @repo, key_prefix: "TICKET")

    refute_predicate build(:key_link, owner: @repo, key_prefix: "ABC-"), :valid?
    refute_predicate build(:key_link, owner: @repo, key_prefix: "abc-"), :valid?
    refute_predicate build(:key_link, owner: @repo, key_prefix: "TICK"), :valid?
    refute_predicate build(:key_link, owner: @repo, key_prefix: "tick"), :valid?

    assert_predicate build(:key_link, owner: @repo, key_prefix: "BCD"), :valid?
    assert_predicate build(:key_link, owner: @repo, key_prefix: "abd"), :valid?
  end

  test "key link create event is published to hydro and audit log" do
    GitHub.context.push(actor: @user)
    prefix = "BAR-"
    template = "https://example/<num>"

    events = assert_performed_audit_entries(count: 1, only: "key_link.create") do
      create(:key_link, owner: @repo, key_prefix: prefix, url_template: template)
    end

    assert_equal last_performed_audit_entries, events

    assert_hydro_published({
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      actor: Hydro::EntitySerializer.user(@user),
      repository: Hydro::EntitySerializer.repository(@repo),
      repository_owner: Hydro::EntitySerializer.user(@repo.owner),
      prefix: prefix,
      template: template,
      spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(GitHub.context[:spamuri_form_signals]),
    }, schema: "github.v1.KeyLinkCreate", count: 1)

    expected_payload = {
      actor: @user.display_login,
      key_prefix: prefix,
      url_template: template,
      is_alphanumeric: true,
      repo: @repo.name_with_display_owner,
    }

    assert_subset_hash expected_payload, events.first
  end

  test "key link destroy event is published to audit log" do
    GitHub.context.push(actor: @user)
    prefix = "BAR-"
    template = "https://example/<num>"
    key_link = create(:key_link, owner: @repo, key_prefix: prefix, url_template: template)

    events = assert_performed_audit_entries(count: 1, only: "key_link.destroy") do
      key_link.destroy
    end

    assert_equal last_performed_audit_entries, events

    expected_payload = {
      actor: @user.display_login,
      key_prefix: prefix,
      url_template: template,
      is_alphanumeric: true,
      repo: @repo.name_with_display_owner,
    }

    assert_subset_hash expected_payload, events.first
  end

  test "is deleted with repository" do
    key_link = create(:key_link, owner: @repo)
    other_key_link = create(:key_link)

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = @repo
      config.expect_destroyed = [key_link]
      config.expect_not_destroyed = [other_key_link]
    end
  end
end
