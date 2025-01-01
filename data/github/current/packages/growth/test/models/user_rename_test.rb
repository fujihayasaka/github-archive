# typed: false
# frozen_string_literal: true

require "test_helper"

class UserRenameTest < GitHub::TestCase
  include AuthenticationHelpers::SAML

  RetiredNamespaceMock = Struct.new(:retired_namespace_exists, :first_retired_namespace)
  fixtures do
    @peter = create(:user, login: "peterparker")
    @repo  = create(:repository, owner: @peter, name: "bigstory")
    @key   =
      create(:public_key,
        key: Sham.ssh_public_key,
        user: @peter,
      )
    @deploy_key = create(:public_key,
      key: Sham.ssh_public_key,
      repository: @repo,
    )
  end

  setup do
    res = RetiredNamespaceMock.new(retired_namespace_exists: false, first_retired_namespace: "")
    ::PackageRegistry::Twirp::MetadataClient.any_instance.stubs(:check_packages_retired_namespace).returns(res)
    reset_repo_root
    example_repo :simple, @repo
  end

  test "should return false if invalid user name" do
    refute @peter.rename(".")
  end

  test "returns false on no name change" do
    refute @peter.rename(@peter.to_s)
  end

  test "returns false when already renaming" do
    @peter.update_attribute :renaming, true
    refute @peter.rename(@peter.to_s)
  end

  test "knows the time of the most recent rename" do
    perform_enqueued_jobs(only: [UserRenameJob]) do
      @peter.rename("spiderman")
      assert_equal "spiderman", @peter.reload.login
      assert_kind_of Time, @peter.renamed_at
    end
  end

  test "can rename more than once" do
    perform_enqueued_jobs(only: [UserRenameJob]) do
      @peter.rename("spiderman")
      assert_equal "spiderman", @peter.reload.login

      @peter.reload.rename("darkspiderman")
      assert_equal "darkspiderman", @peter.reload.login
    end
  end

  test "creates redirect entries for repositories" do
    perform_enqueued_jobs(only: [UserRenameJob]) do
      @peter.rename("spiderman")
      assert_equal 1, @repo.redirects.count
      assert_equal "peterparker/bigstory", @repo.redirects.first.repository_name
    end
  end

  test "renaming a user also renames the stealth email used for outbound email" do
    perform_enqueued_jobs(only: [UserRenameJob]) do
      @peter.primary_user_email.toggle_visibility
      old_stealth_email = @peter.emails.with_role("stealth").to_s
      @peter.rename("spiderman")
      assert @peter.outbound_email != old_stealth_email, "Should not be using old stealth email"
      assert_nil UserEmail.find_by_email(old_stealth_email), "Old stealth email should not exist"
      assert_match /spiderman/, @peter.outbound_email, "Outbound email should be using renamed stealth email"
    end
  end

  # Regression https://github.com/github/github/issues/32530
  test "renaming a user renames their stealth email, even when stealth emails were turned off" do
    @peter.primary_user_email.toggle_visibility # turn to private
    @peter.primary_user_email.toggle_visibility # turn back to public
    @peter.rename!("spiderman")
    assert_equal "#{@peter.id}+spiderman@users.noreply.#{GitHub.host_name}", @peter.emails.with_role("stealth").to_s
  end

  if GitHub.sponsors_enabled?
    test "updates the user's SponsorsListing slug and its Zuora product" do
      old_slug = SponsorsListing.slug_for(@peter.login)
      new_login = "spiderman"
      new_slug = SponsorsListing.slug_for(new_login)
      listing = create(:sponsors_listing, sponsorable: @peter)
      assert_equal old_slug, listing.slug

      listing.expects(:update_zuora_product_and_maintainer_name).once.with(
        old_slug: old_slug,
        new_slug: new_slug,
        new_login: new_login,
      ).returns(true)

      @peter.rename!(new_login)

      assert_equal new_slug, listing.reload.slug
    end
  end

  test "doesn't allow renaming if it results in a retired namespace" do
    user = create(:user)
    user_repo = create :repository, owner: user, name: @repo.name

    RetiredNamespace.create_from_repository!(user_repo)
    user.destroy

    refute @peter.rename "#{user.login}"
  end

  test "allow renaming that conflicts with a retired namespace if it is claimable" do
    login = "lalalalisa"
    user = create(:user, login: login)
    user_repo = create(:repository, owner: user)
    RetiredNamespace.create_from_repository!(user_repo)

    perform_enqueued_jobs(only: [UserRenameJob]) do
      user.rename("mona")
    end

    assert user.reload.rename(login)
  end

  test "does not allow renaming if repository name conflicts with retired namespace" do
    login = "twicestan"
    repo_name = "dahyun"
    user = create(:verified_user, login: login)
    repo = create(:repository, owner: user, name: repo_name)
    namespace = create(:retired_namespace, owner: user, name: repo_name)

    # Set owner_id to NULL to match reproduction: https://github.com/github/communities/issues/1126#issuecomment-1137318902
    namespace.update!(owner_id: nil)

    user.rename!("formertwicestan")

    other_user = create(:verified_user)
    other_repo = create(:repository, owner: other_user, name: repo_name)
    refute other_user.rename(login)

    expected = "Username change was not successful. The repository name twicestan/dahyun has been retired and cannot be reused"
    assert_equal expected, other_user.errors.full_messages.to_sentence
  end

  test "does not allow renaming if repository name conflicts with retired package namespace when feature flag is enabled" do
    GitHub.flipper[:packages_namespace_retirement].enable
    login = "seok"
    user = create(:verified_user, login: login)
    user.rename!("jin")

    res = RetiredNamespaceMock.new(retired_namespace_exists: true, first_retired_namespace: "epiphany")
    ::PackageRegistry::Twirp::MetadataClient.any_instance.stubs(:check_packages_retired_namespace).returns(res)
    other_user = create(:verified_user)
    refute other_user.rename(login)

    expected = "Username change was not successful. The package name seok/epiphany has been retired and cannot be reused"
    assert_equal expected, other_user.errors.full_messages.to_sentence
  end

  test "does not retire namespace for user pages repo on rename" do
    stub_pond_response({ data: { count: 1000 } })
    user = create(:verified_user, login: "collei")
    repo_name = "collei.#{GitHub.pages_host_name_v2}"
    repo = create(:repository, owner: user, name: repo_name)
    refute RetiredNamespace.retired?("collei/#{repo_name}")

    user.rename!("forest-ranger-collei")

    refute RetiredNamespace.retired?("collei/#{repo_name}")
  end

  test "doesn't allow renaming if emu user" do
    user = create(:emu)
    old_login = user.login

    result = user.rename("lalalalisa")

    refute result
    assert_equal old_login, user.login
  end unless GitHub.single_business_environment?

  test "doesn't allow renaming if GHES SCIM user" do
    setup_saml_auth_mode(with_scim: true)

    user = create(:ghes_scim_user)
    old_login = user.login

    result = user.rename("lalalalisa")

    refute result
    assert_equal old_login, user.login
  end if GitHub.single_business_environment?

  private

  def stub_pond_response(body)
    stub_request(:get, /pond.test/).
      to_return({
        status: 200,
        body: body.to_json,
        headers: { "content-type" => "json" },
      })
  end
end
