# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationDangerousRenameTest < GitHub::TestCase
  fixtures do
    @org_admin      = create(:user, login: "org-admin")
    @org            = create(:organization, admin: @org_admin, plan: "bronze")
    @spammyorg      = create(:organization, admin: @org_admin, plan: "bronze", spammy: true)
  end

  test "disallows renaming org when new login contains invalid characters" do
    refute @org.rename("grin🤓")
    assert_nil @org.renamed_at
    assert_equal \
      "Organization name may only contain alphanumeric characters or single hyphens, and cannot begin or end with a hyphen",
      @org.errors.full_messages.to_sentence
  end

  test "instruments org.rename event" do
    events = subscribe "org.rename"

    expected_payload = {
      org: "foo",
      org_id: @org.id,
      old_login: @org.login,
      actor: "foo",
      actor_id: @org.id,
      rename_reason: nil,
      rename_notes: nil,
    }

    @org.rename!("foo")

    assert event = events.pop, "expected an event"
    assert_equal expected_payload, event.payload
  end

  unless GitHub.enterprise?
    test "cannot rename spammy org" do
      refute @spammyorg.rename!("foo")
    end
  end
end

class OrganizationRenameTest < GitHub::TestCase
  PackageNamespaceResultMock = Struct.new(
    :retired_namespace_exists,
    :first_retired_namespace
  )
  setup do
    res = PackageNamespaceResultMock.new(retired_namespace_exists: false, first_retired_namespace: "")
    ::PackageRegistry::Twirp::MetadataClient.any_instance.stubs(:check_packages_retired_namespace).returns(res)
  end

  test "disallow renaming if archived org" do
    org = create :archived_organization, admin: create(:user)

    assert_no_changes "org.login" do
      perform_enqueued_jobs(only: [UserRenameJob]) do
        refute org.rename("lalalalisa")
        assert_nil org.renamed_at
        assert_equal "This organization cannot be renamed because it is archived.", org.errors.full_messages.to_sentence
      end
    end
  end

  test "allow renaming if GHES/GHEC org" do
    org = create :organization, admin: create(:user)

    perform_enqueued_jobs(only: [UserRenameJob]) do
      result = org.rename("lalalalisa")
      org.reload

      assert result
      assert_equal "lalalalisa", org.login
      assert_kind_of Time, org.renamed_at
    end
  end

  test "allow renaming if emu org" do
    user = create :emu, :owner
    org = create :organization, business: user.enterprise_managed_business, admin: user

    perform_enqueued_jobs(only: [UserRenameJob]) do
      result = org.rename("lalalalisa")
      org.reload

      assert result
      assert_equal "lalalalisa", org.login
      assert_kind_of Time, org.renamed_at
    end
  end unless GitHub.single_business_environment?

  test "allow renaming if GHES SCIM org" do
    user = create :ghes_scim_user, :scim
    org = create :organization, business: GitHub.global_business, admin: user

    perform_enqueued_jobs(only: [UserRenameJob]) do
      result = org.rename("lalalalisa")
      org.reload

      assert result
      assert_equal "lalalalisa", org.login
      assert_kind_of Time, org.renamed_at
    end
  end if GitHub.single_business_environment?
end
