# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesSecurityCenterCodeScanningBusinessQueryTest < GitHub::TestCase

  context "#organization_names" do
    test "returns all org values" do
      assert_empty create_query("is:open").organization_names
      assert_empty create_query("org:").organization_names
      assert_equal ["abc"], create_query("org:abc").organization_names
      assert_equal %w[abc def], create_query("org:abc,def").organization_names
      assert_equal %w[abc def], create_query("org:abc org:def").organization_names
      assert_equal ["abc"], create_query("org:abc -org:def").organization_names
    end
  end

  context "#excluded_organization_names" do
    test "returns a list of excluded org names" do
      assert_empty create_query("is:open").excluded_organization_names
      assert_empty create_query("-org:").excluded_organization_names
      assert_empty create_query("org:abc").excluded_organization_names
      assert_equal %w[abc def], create_query("-org:abc,def").excluded_organization_names
      assert_equal ["def"], create_query("org:abc -org:def").excluded_organization_names
    end
  end

  context "#has_org?" do
    test "returns true if org is in the list" do
      query = create_query("org:abc,def")
      assert query.has_org?("abc")
      assert query.has_org?("def")
      refute query.has_org?("ghi")
    end
  end

  context "#is_valid?" do
    test "returns true if query string is empty" do
      assert create_query("").is_valid?
    end

    test "returns false if parent logic would have returned false" do
      parent = Search::Queries::SecurityCenter::CodeScanningBaseQuery.new("is:foo")
      query = create_query("is:foo")
      assert_equal parent.is_valid?, query.is_valid?
      refute query.is_valid?
    end

    test "returns true if repo has a valid NWO" do
      assert create_query("repo:org/repo").is_valid?
    end

    test "returns true if repo has any value that is a valid NWO" do
      assert create_query("repo:bad,org/repo,another-bad").is_valid?
    end

    test "returns false if repo only has bad NWOs" do
      refute create_query("repo:bad").is_valid?
    end
  end

  context "#repository_names_with_owner" do
    test "returns hash of provided NWO" do
      query = create_query("repo:org/repo")
      assert_equal({ "org" => ["repo"] }, query.repository_names_with_owner)
    end

    test "returns hash of provided NWOs" do
      query = create_query("repo:org/repo,org/repo2,org2/repo")
      assert_equal({ "org" => %w[repo repo2], "org2" => ["repo"] }, query.repository_names_with_owner)
    end

    test "returns empty hash if no NWOs are provided" do
      query = create_query("is:open")
      assert_equal({}, query.repository_names_with_owner)
    end

    test "returns empty hash if only malformed NWOs are provided" do
      query = create_query("repo:bad,bad2")
      assert_equal({}, query.repository_names_with_owner)
    end

    test "returns hash of only valid NWOs if a mix are provided" do
      query = create_query("repo:bad,org/good,bad2")
      assert_equal({ "org" => ["good"] }, query.repository_names_with_owner)
    end

    context "#has_nwo?" do
      test "returns true if provided NWO is in the list" do
        query = create_query("repo:my-org/my-repo,my-other-org/my-other-repo")

        assert query.has_nwo?("my-org/my-repo")
        assert query.has_nwo?("my-other-org/my-other-repo")

        refute query.has_nwo?("my-other-org/my-repo")
        refute query.has_nwo?("my-org/my-other-repo")

        # Malformed NWO in the filter
        query = create_query("repo:my-org/my-repo,my-other-repo")

        assert query.has_nwo?("my-org/my-repo")
      end

      test "returns false for malformed provided NWO" do
        query = create_query("repo:my-org/my-repo,my-other-org/my-other-repo")

        refute query.has_nwo?("my-org")
        refute query.has_nwo?("my-org/")
        refute query.has_nwo?("my-repo")
        refute query.has_nwo?("/my-repo")
        refute query.has_nwo?("my-org/my-repo,my-other-org/my-other-repo")
        refute query.has_nwo?("")

        # Malformed NWO in the filter
        query = create_query("repo:my-org/my-repo,my-other-repo")

        refute query.has_nwo?("my-other-repo")
        refute query.has_nwo?("my-org/my-repo,my-other-repo")
        refute query.has_nwo?("")
      end
    end
  end

  context "#excluded_repository_names_with_owner" do
    test "returns hash of provided NWO" do
      query = create_query("-repo:org/repo")
      assert_equal({ "org" => ["repo"] }, query.excluded_repository_names_with_owner)
    end

    test "returns hash of provided NWOs" do
      query = create_query("-repo:org/repo,org/repo2,org2/repo")
      assert_equal({ "org" => %w[repo repo2], "org2" => ["repo"] }, query.excluded_repository_names_with_owner)
    end

    test "returns empty hash if no NWOs are provided" do
      query = create_query("is:open")
      assert_equal({}, query.excluded_repository_names_with_owner)
    end

    test "returns empty hash if only malformed NWOs are provided" do
      query = create_query("-repo:bad,bad2")
      assert_equal({}, query.excluded_repository_names_with_owner)
    end

    test "returns hash of only valid NWOs if a mix are provided" do
      query = create_query("-repo:bad,org/good,bad2")
      assert_equal({ "org" => ["good"] }, query.excluded_repository_names_with_owner)
    end
  end

  def create_query(query)
    Search::Queries::SecurityCenter::CodeScanningBusinessQuery.new(query)
  end
end
