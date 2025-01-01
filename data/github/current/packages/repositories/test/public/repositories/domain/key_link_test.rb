# typed: true
# frozen_string_literal: true

require "test_helper"

class Repositories::Domain::KeyLinkTest < GitHub::TestCase
  include GitHub::DatabaseQueryWarningsTestHelpers

  fixtures do
    @key_link = create(:key_link)
  end

  setup do
    @domain = T.let(Repositories::Domain::KeyLink.new(:test), T.nilable(Repositories::Domain::KeyLink))
  end

  sig { returns(Repositories::Domain::KeyLink) }
  def domain
    T.must(@domain)
  end

  context "#by_id" do
    test "finds the indicated key link" do
      link = domain.by_id(@key_link.id, repo_id: @key_link.owner_id)
      assert_equal @key_link.id, T.must(link).id
    end

    test "returns nil if the key link does not exist" do
      assert_nil domain.by_id(0, repo_id: 99)
    end
  end

  context "#list_for_repo" do
    test "lists the repo's keylinks" do
      attrs = Repositories::CreateKeyLinkAttributes.new(
        key_prefix: "another",
        url_template: "https://example2.com/<num>"
      )
      result = T.cast(domain.create(attrs, repo_id: @key_link.owner_id), GH::Result::Ok[Repositories::IKeyLink])

      links = domain.list_for_repo(@key_link.owner_id)
      assert_equal 2, links.size
      assert_equal @key_link.id, T.must(links.first).id
      assert_equal result.value.id, T.must(links.to_a.last).id
    end

    test "returns an empty list if the repo not exist" do
      assert_empty domain.list_for_repo(0)
    end
  end

  context "#destroy" do
    test "destroys the indicated key link" do
      result = domain.destroy(@key_link.id, repo_id: @key_link.owner_id)
      assert_kind_of(GH::Result::Ok, result)
    end

    test "reports when the key link is missing" do
      result = domain.destroy(0, repo_id: @key_link.owner_id + 34)
      assert_kind_of(GH::Result::Error::NotFound, result)
    end
  end

  context "#create" do
    test "creates the key link" do
      attrs = Repositories::CreateKeyLinkAttributes.new(
        key_prefix: "hey",
        url_template: "https://example.com/<num>",
        is_alphanumeric: false
      )
      result = T.cast(domain.create(attrs, repo_id: @key_link.owner_id), GH::Result::Ok[Repositories::IKeyLink])

      assert_equal "hey", result.value.key_prefix
      assert_equal "https://example.com/<num>", result.value.url_template
      refute result.value.is_alphanumeric?

      attrs = Repositories::CreateKeyLinkAttributes.new(
        key_prefix: "another",
        url_template: "https://example2.com/<num>"
      )
      result = T.cast(domain.create(attrs, repo_id: @key_link.owner_id), GH::Result::Ok[Repositories::IKeyLink])
      assert result.value.is_alphanumeric?
    end

    test "refuses to create with invalid url template" do
      attrs = Repositories::CreateKeyLinkAttributes.new(
        key_prefix: "hey",
        url_template: "https://example.com/missing-num",
      )
      result = T.cast(domain.create(attrs, repo_id: @key_link.owner_id), GH::Result::Error::Validation[Repositories::IKeyLink])
      assert result.model.errors[:url_template].any?
    end

    test "refuses to create with blank prefix" do
      attrs = Repositories::CreateKeyLinkAttributes.new(
        key_prefix: "",
        url_template: "https://example2.com/<num>"
      )
      result = T.cast(domain.create(attrs, repo_id: @key_link.owner_id), GH::Result::Error::Validation[Repositories::IKeyLink])
      assert result.model.errors[:key_prefix].any?
    end

    test "does not create autolink that overlaps existing prefix" do
      attrs = Repositories::CreateKeyLinkAttributes.new(
        key_prefix: "hey-",
        url_template: "https://example.com/<num>"
      )
      assert_kind_of GH::Result::Ok, domain.create(attrs, repo_id: @key_link.owner_id)

      attrs = Repositories::CreateKeyLinkAttributes.new(
        key_prefix: "hey",
        url_template: "https://example.com/<num>"
      )
      result = T.cast(domain.create(attrs, repo_id: @key_link.owner_id), GH::Result::Error::Validation[Repositories::IKeyLink])
      assert_includes result.model.errors.first.message, "starts with the new prefix, which could cause overlap"

      attrs = Repositories::CreateKeyLinkAttributes.new(
        key_prefix: "hey--",
        url_template: "https://example.com/<num>"
      )
      result = T.cast(domain.create(attrs, repo_id: @key_link.owner_id), GH::Result::Error::Validation[Repositories::IKeyLink])
      assert_includes result.model.errors.first.message, "The new prefix starts with the existing prefix"
    end
  end
end
