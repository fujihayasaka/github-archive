# typed: true
# frozen_string_literal: true

require "test_helper"

class FundingLinksTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
    @non_funding_repo = create(:repository)
    @blob = <<~YAML
    github: monalisa
    patreon: patreon-testing-username-github
    open_collective: opencollective-testing-username
    ko_fi: ko-fi-testing-username
    tidelift: tidelift-testing-username
    community_bridge: community-bridge-testing-username
    liberapay: liberapay-testing-username
    issuehunt: issuehunt-testing-username
    lfx_crowdfunding: lfx-crowdfunding-testing-username
    polar: polar-testing-username
    buy_me_a_coffee: buy-me-a-coffee-testing-username
    thanks_dev: thanks-dev-testing-username
    custom: https://custom.testing
    YAML
  end

  setup do
    example_repo(:funding_links, @repo)
    example_repo(:simple, @non_funding_repo)
  end

  context ".template" do
    test "generates a valid funding template" do
      yaml = YAML.safe_load(FundingLinks.template)
      refute_predicate yaml, :blank?
      assert_equal yaml.keys, FundingPlatforms::ALL.keys.map(&:to_s)
    end
  end

  context ".for" do
    test "returns parsed FUNDING object when one exists" do
      assert FundingLinks.for(repository: @repo).config.keys.size
    end

    test "returns parsed FUNDING object for valid blob" do
      assert FundingLinks.for(blob: @blob).config.keys.size
    end

    test "returns empty FUNDING object when config does not exist" do
      other_repo = create(:repository)
      assert_empty FundingLinks.for(repository: other_repo).config
    end

    test "returns empty FUNDING object if file name is not yml" do
      repo = create(:repository)
      ref = repo.heads.find_or_build("master")
      ref.append_commit({ message:  "add FUNDING.md", committer: repo.owner }, repo.owner) do |files|
        files.add("FUNDING.md", @blob)
      end

      assert_empty FundingLinks.for(repository: repo).config
    end
  end

  context "#config" do
    test "is empty when no values are configured" do
      repo = create :repository, from_example: :funding_links_empty

      config = FundingLinks.for(repository: repo).config
      assert_empty config
    end

    test "is empty when an incorrect, but valid YAML format is configured" do
      repo = create :repository, from_example: :funding_links_array

      assert_empty FundingLinks.for(repository: repo).config
    end

    test "is empty when the FUNDING.yml file is not a hash" do
      repo = create :repository, from_example: :funding_file_non_hash

      assert_empty FundingLinks.for(repository: repo).config
    end
  end

  context "#sponsorable_users" do
    test "respects order of sponsors_logins" do
      sponsors_logins = %w[deer bee cat apple]
      sponsors_logins.each do |login|
        create(:user, :sponsorable, login: login)
      end

      blob = <<~YAML
      github: [deer, bee, cat, apple]
      YAML

      links = FundingLinks.for(blob: blob)
      assert_equal sponsors_logins, links.sponsorable_users.map(&:login)
    end

    test "is case insensitive" do
      sponsors_logins = %w[Apple cAt deer]
      sponsors_logins.each do |login|
        create(:user, :sponsorable, login: login)
      end
      sponsorables = User.where(login: sponsors_logins).order(:login)

      blob = <<~YAML
      github: [apple, cat, deer]
      YAML

      links = FundingLinks.for(blob: blob)
      assert_equal sponsorables, links.sponsorable_users
    end

    test "doesn't blow up on non-string sponsors logins" do
      sponsors_logins = [1, { fish: 1 }, OpenStruct.new]

      blob = <<~YAML
      github: [1, { fish: 1 }]
      YAML

      links = FundingLinks.for(blob: blob)
      assert_empty links.sponsorable_users
    end

    test "works with single user" do
      sponsorable = create(:user, :sponsorable, login: "cat")

      blob = <<~YAML
      github: cat
      YAML

      links = FundingLinks.for(blob: blob)
      assert_equal [sponsorable], links.sponsorable_users
    end
  end

  context "#sponsorable_org" do
    test "returns sponsorable org" do
      org = create(:organization, :sponsorable)
      blob = "github: [#{org}]"

      links = FundingLinks.for(blob: blob)

      assert_equal org, links.sponsorable_org
    end

    test "returns nothing if org is not sponsorable" do
      org = create(:organization)
      blob = "github: [#{org}]"

      links = FundingLinks.for(blob: blob)

      assert_nil links.sponsorable_org
    end

    test "doesn't count against the maximum number of users" do
      num_users = FundingLinks::MAX_GITHUB_USER_SPONSORABLES
      users = create_list(:user, num_users, :sponsorable)
      user_logins = users.map(&:login)

      org = create(:organization, :sponsorable)

      blob = <<~YAML
        github: [#{user_logins.join(", ")}, #{org.login}]
      YAML

      links = FundingLinks.for(blob: blob)

      assert_equal FundingLinks::MAX_GITHUB_USER_SPONSORABLES, links.sponsorable_users.count
      assert_equal user_logins, links.sponsorable_users.map(&:login)
      refute_nil links.sponsorable_org
      assert_equal org.login, T.must(links.sponsorable_org).login
    end
  end

  context "#lone_sponsorable" do
    test "returns the one sponsorable user" do
      user = create(:user, :sponsorable)
      links = FundingLinks.for(blob: "github: #{user}")

      result = links.lone_sponsorable

      assert_instance_of User, result
      assert_equal user.id, T.must(result).id
    end

    test "returns the one sponsorable organization" do
      org = create(:organization, :sponsorable)
      links = FundingLinks.for(blob: "github: #{org}")

      result = links.lone_sponsorable

      assert_instance_of Organization, result
      assert_equal org.id, T.must(result).id
    end

    test "returns nil when there's more than one sponsorable" do
      user = create(:user, :sponsorable)
      org = create(:organization, :sponsorable)
      links = FundingLinks.for(blob: "github: [#{org}, #{user}]")

      assert_nil links.lone_sponsorable
    end

    test "returns nil when there are no sponsorables" do
      links = FundingLinks.for(blob: "patreon: patreon-testing-username-github")
      assert_nil links.lone_sponsorable
    end
  end

  context "#sponsorable_ids" do
    test "returns [] if no valid logins provided" do
      links = FundingLinks.for(repository: @repo)
      assert_empty links.sponsorable_ids
    end

    test "returns [] if no sponsorable logins provided" do
      user = create(:user, login: "monalisa")
      links = FundingLinks.for(repository: @repo)

      assert_empty links.sponsorable_ids
    end

    test "returns IDs of sponsorable users" do
      user = create(:user, :sponsorable, login: "monalisa")
      links = FundingLinks.for(repository: @repo)

      assert_equal [user.id], links.sponsorable_ids
    end
  end

  context "#external_funding_config" do
    test "with invalid config" do
      links = FundingLinks.for(blob: "?")
      assert_empty links.external_funding_config
    end

    test "with GH only funding" do
      links = FundingLinks.for(blob: "github: monalisa")
      assert_empty links.external_funding_config
    end

    test "with all funding platforms" do
      links = FundingLinks.for(blob: @blob)
      external_funding_keys = FundingPlatforms::ALL.except(:github).keys.map(&:to_s)
      assert_equal external_funding_keys, links.external_funding_config.keys
    end
  end

  context "#has_multiple_sponsorables_or_external_links?" do
    test "returns true when there's more than one sponsorable" do
      org = create(:organization, :sponsorable)
      user = create(:user, :sponsorable)

      links = FundingLinks.for(blob: "github: [#{org}, #{user}]")

      assert_predicate links, :has_multiple_sponsorables_or_external_links?
    end

    test "returns true when there is an external funding account" do
      links = FundingLinks.for(blob: "patreon: patreon-testing-username-github")
      assert_predicate links, :has_multiple_sponsorables_or_external_links?
    end

    test "returns false when there is only one sponsorable and no external funding accounts" do
      org = create(:organization, :sponsorable)
      links = FundingLinks.for(blob: "github: #{org}")
      refute_predicate links, :has_multiple_sponsorables_or_external_links?
    end
  end

  context "#errors" do
    test "returns an error if one of the logins is not sponsorable" do
      links = FundingLinks.for(blob: "github: fake-user")
      assert_equal [FundingLinks::NON_SPONSORABLE_ERROR], links.errors
    end

    test "returns an error if there are too many sponsorable logins" do
      limit = FundingLinks::MAX_GITHUB_SPONSORABLES + 1
      sponsorables = create_list(:organization, limit, :sponsorable)
      links = FundingLinks.for(blob: "github: [#{sponsorables.map(&:login).join(", ")}]")
      assert_equal [FundingLinks::SPONSORABLE_LIMIT_EXCEEDED_ERROR], links.errors
    end
  end

  context "#external_funding_accounts" do
    test "does not include array for supported accounts" do
      links = FundingLinks.for(blob: "patreon: [one, two]\ntidelift: three")
      h = { "tidelift" => "three" }
      assert_equal h, links.external_funding_accounts
    end

    test "does include array of custom accounts" do
      blob = "custom: [\"https://testing.funding\", \"https://funding.testing\"]"
      h =  { "custom" => ["https://testing.funding", "https://funding.testing"] }

      links = FundingLinks.for(blob: blob)
      assert_equal h, links.external_funding_accounts
    end

    test "does not include number accounts" do
      links = FundingLinks.for(blob: "patreon: 12345\ntidelift: three")
      h = { "tidelift" => "three" }
      assert_equal h, links.external_funding_accounts
    end

    test "does not include unsupported accounts" do
      links = FundingLinks.for(blob: "notathing: one\ntidelift: three")
      h = { "tidelift" => "three" }
      assert_equal h, links.external_funding_accounts
    end

    test "does not include custom links with javascript" do
      links = FundingLinks.for(blob: "custom: javascript:alert(1)\ntidelift: three")
      h = { "tidelift" => "three" }
      assert_equal h, links.external_funding_accounts
    end

    test "ignores non-whitelisted keys" do
      blob = "cheese: good\nfriends: forever\npatreon: github"
      external_links = FundingLinks.for(blob: blob).external_funding_accounts
      refute_empty external_links
      assert_equal external_links.keys.size, 1
      assert external_links["patreon"], "Expected white-listed key, got nil"
      refute external_links["cheese"], "Unexpected key 'cheese'"
    end

    test "is empty when no values are configured" do
      blob = "patreon:\n"
      links = FundingLinks.for(blob: blob).external_funding_accounts
      assert_empty links
    end

    test "is empty when an incorrect, but valid YAML format is configured" do
      blob = "- one\n- two"
      links = FundingLinks.for(blob: blob).external_funding_accounts
      assert_empty links
    end
  end
end
