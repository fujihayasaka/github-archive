# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesMarketplaceQueryTest < GitHub::TestCase
  fixtures do
    setup_search
    @user  = create(:user)

    @marketplace_listing = create(:marketplace_listing, :verified, name: "Acme, inc", listable: create(:integration, owner: @user))
    @unverified_listing = create(:marketplace_listing, :unverified, listable: create(:integration, owner: @user), name: "acme unverified")
    @verification_pending_from_unverified_listing = create(:marketplace_listing, :verification_pending_from_unverified, listable: create(:integration, owner: @user))
    @repository_action = create(:repository_action, :listed, name: "Acme Actions", repository: create(:repository, owner: @user))
    @verified_repository_action = create(:repository_action, :verified, :listed, name: "Verified Acme Actions")
    @sponsorable_listing = create(:marketplace_listing, :verified, listable: create(:integration, owner: @user))
    @verified_org = create(:organization)
    @unverified_org = create(:organization)
    @verified_creator_unverified_listing = create(:marketplace_listing, :unverified, :verified_publisher, listable: create(:integration, owner: @verified_org), name: "vcul")
    @verified_creator_verified_listing = create(:marketplace_listing, :verified, :verified_publisher, listable: create(:integration, owner: @unverified_org), name: "vcvl")

    @marketplace_listing_recommendation1 = create(:marketplace_listing, :verified, :verified_publisher,  name: "Package, inc")
    recommended_list = [@marketplace_listing_recommendation1]
    # rubocop:todo GitHub/DoNotUseGlobalKv
    GitHub.kv.set("marketplace/recommendations", recommended_list.pluck(:id).to_json)
    # rubocop:enable GitHub/DoNotUseGlobalKv

    @org = create(:organization)
    @marketplace_org_listing = create(:marketplace_listing, :verified, listable: create(:oauth_application, user: @org), name: "Acme org listing")
    @unverified_org_listing = create(:marketplace_listing, :unverified, listable: create(:integration, owner: @org))
    @verification_pending_from_unverified_org_listing = create(:marketplace_listing, :verification_pending_from_unverified, listable: create(:oauth_application, user: @org))
    @repository_org_action = create(:repository_action, :listed, repository: create(:repository, owner: @org))

    mock_azure_model_gpt4 = GitHubModels::Types::Static::GPT4
    @model_catalog_item = AzureModels::CatalogItem.create(key: "gpt4", value: { model: mock_azure_model_gpt4 }.to_json)
  end

  setup do
    reset_cache
    make_searchable(@marketplace_listing, type: "marketplace_listing")
    make_searchable(@unverified_listing, type: "marketplace_listing")
    make_searchable(@verification_pending_from_unverified_listing, type: "marketplace_listing")
    make_searchable(@repository_action, type: "repository_action")
    make_searchable(@verified_repository_action, type: "repository_action")
    make_searchable(@sponsorable_listing, type: "marketplace_listing")
    make_searchable(@verified_creator_unverified_listing, type: "marketplace_listing")
    make_searchable(@verified_creator_verified_listing, type: "marketplace_listing")

    make_searchable(@marketplace_listing_recommendation1, type: "marketplace_listing")

    make_searchable(@marketplace_org_listing, type: "marketplace_listing")
    make_searchable(@unverified_org_listing, type: "marketplace_listing")
    make_searchable(@verification_pending_from_unverified_org_listing, type: "marketplace_listing")
    make_searchable(@repository_org_action, type: "repository_action")

    make_searchable(@model_catalog_item, type: "azure_model")

    GitHub.flipper[:dependents_count_marketplace].disable
  end

  teardown do
    teardown_search
  end

  def publisher_user_query
    "owner_login.raw:#{@user.login}"
  end

  def publisher_org_query
    "owner_login.raw:#{@org.login}"
  end

  context "Search scoped by type", skip_enterprise: true do
    test "marketplace-tools type returns marketplace listings, actions, and models" do
      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "marketplace-tools", per_page: 20)

      results = query.execute.results.map { |result| result["_model"] }

      assert_includes results, @marketplace_listing
      assert_includes results, @repository_action
      assert_includes results, @verified_repository_action
      assert_includes results, @model_catalog_item
    end

    test "marketplace type only returns marketplace listings" do
      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "marketplace")

      results = query.execute.results.map { |result| result["_model"] }

      assert_includes results, @marketplace_listing
      refute_includes results, @repository_action
      refute_includes results, @verified_repository_action
      refute_includes results, @model_catalog_item
    end

    test "type is case insensitive" do
      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "marketplace")
      query2 = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "Marketplace")

      assert_equal(query.search_type_filter, query2.search_type_filter)
    end

    test "can search for models by name" do
      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "marketplace-tools")
      query.phrase = "gpt"

      results = query.execute.results.map { |result| result["_model"] }

      assert_includes results, @model_catalog_item
    end

    test "can query for Marketplace listings only" do

      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "Marketplace")

      results = query.execute.results.map { |result| result["_model"] }

      assert_includes results, @marketplace_listing
    end

    test "returns unverified marketplace listings" do

      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "Marketplace", per_page: 20)

      results = query.execute.results.map { |result| result["_model"] }

      assert_includes results, @marketplace_listing
      assert_includes results, @unverified_listing
      assert_includes results, @verification_pending_from_unverified_listing
    end

    test "returns verified marketplace listings" do

      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "Marketplace",  verification_state: "verified")

      results = query.execute.results.map { |result| result["_model"] }

      assert_includes results, @marketplace_listing
      refute_includes results, @unverified_listing
      refute_includes results, @verification_pending_from_unverified_listing

      # current decision is to give more precedence to verified state
      assert_includes results, @verified_creator_verified_listing
      refute_includes results, @verified_creator_unverified_listing
    end

    test "recommended apps are ordered before others" do

      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "Marketplace",  verification_state: "verified")

      results = query.execute.results.map { |result| [result["_model"], result["_score"]] }.to_h

      # current decision is to give more precedence to verified state
      assert_operator results[@marketplace_listing_recommendation1], :>, results[@marketplace_listing]
    end

    test "returns unverified repository actions" do
      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "repository-action", verification_state: "unverified")

      results = query.execute.results.map { |result| result["_model"] }

      assert_includes results, @repository_action
    end

    test "prunes actions with private repos" do
      # nb: this should not be possible but we saw it in the wild
      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "repository-action")
      query.phrase = "Acme"
      results = query.execute.results.map { |result| result["_model"] }
      assert_includes results, @repository_action

      # updates directly to avoid running callbacs that would delist action
      Repository.where(id: @repository_action.repository.id).update_all(public: false)

      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "repository-action")
      query.phrase = "Acme"
      results = query.execute.results.map { |result| result["_model"] }
      refute_includes results, @repository_action
    end

    test "can query by repository action by name with feature flag enabled" do
      other_repository_action = create(:repository_action, :listed, name: "notagoodone")
      make_searchable(other_repository_action, type: "repository_action")

      delisted_repository_action = create(:repository_action, state: :delisted, name: "Acme action")
      make_searchable(delisted_repository_action, type: "repository_action")

      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "repository-action")
      query.phrase = "Acme"

      results = query.execute.results.map { |result| result["_model"] }
      assert_includes results, @repository_action
      refute_includes results, other_repository_action
      refute_includes results, delisted_repository_action
      refute_includes results, @marketplace_listing
    end

    test "repo actions search based on owner login" do
      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "repository-action")
      query.phrase = @repository_action.owner.login

      results = query.execute.results.map { |result| result["_model"] }
      assert_equal [
        @repository_action,
      ], results
    end

    test "repo actions search based on owner name" do
      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "repository-action")
      query.phrase = @repository_action.owner.name

      results = query.execute.results.map { |result| result["_model"] }
      assert_equal [
        @repository_action,
      ], results
    end

    test "verified repository actions are boosted above non-verified actions if query is not blank" do
      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "repository-action")
      query.phrase = "Acme"

      results = query.execute.results.map { |result| [result["_model"], result["_score"]] }.to_h
      assert_same_elements [@verified_repository_action, @repository_action], results.keys

      # Verified score will be greater than the non-verfied score
      assert_operator results[@verified_repository_action], :>, results[@repository_action]
    end

    test "verified repository actions are boosted above non-verified actions if query is empty when not microsoft or github owned" do
      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "repository-action")
      query.phrase = ""

      results = query.execute.results.map { |result| [result["_model"], result["_score"]] }.to_h
      assert_same_elements [@verified_repository_action, @repository_action, @repository_org_action], results.keys

      # Verified score will be greater than the non-verfied score
      assert_operator results[@verified_repository_action], :>, results[@repository_action]
    end

    test "azure and github repository actions are not listed below other verified actions if query is not empty" do
      azure = create(:organization, login: "azure")
      github = create(:organization, login: "actions")

      azure_action = create(
        :repository_action,
        :verified,
        :listed,
        repository: create(:repository, owner: azure),
        name: "Verified Acme Actions 2",
      )
      make_searchable(azure_action, type: "repository_action")

      github_action = create(
        :repository_action,
        :verified,
        :listed,
        repository: create(:repository, owner: github),
        name: "Verified Acme Actions 3",
      )
      make_searchable(github_action, type: "repository_action")

      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "repository-action")
      query.phrase = "Acme"

      results = query.execute.results.map do |result|
        [result["_model"], result["_score"]]
      end.to_h

      # Make sure it's the models we expect
      assert_same_elements [
        @verified_repository_action,
        azure_action,
        github_action,
        @repository_action,
      ], results.keys

      # Make sure the verified ones are all relatively equal
      assert_in_delta results[@verified_repository_action], results[azure_action], 0.1
      assert_in_delta results[github_action], results[azure_action], 0.1

      # Make sure the unverified one is scored less than the verified ones
      assert_operator results[@repository_action], :<, results[github_action]
    ensure
      # We must delete these because they will pollute the index otherwise and be high ranking as they are verified.
      # The index is only setup and deleted one for this entire file, so we have to do this manually.
      RemoveFromSearchIndexJob.perform_now("repository_action", github_action.id)
      github_action.destroy!
      RemoveFromSearchIndexJob.perform_now("repository_action", azure_action.id)
      azure_action.destroy!
    end

    test "azure and github repository actions are listed below other verified actions with blank query" do
      azure = create(:organization, login: "azure")
      github = create(:organization, login: "actions")

      azure_action = create(
        :repository_action,
        :verified,
        :listed,
        repository: create(:repository, owner: azure),
        name: "Verified Acme Actions 2",
      )
      make_searchable(azure_action, type: "repository_action")

      github_action = create(
        :repository_action,
        :verified,
        :listed,
        repository: create(:repository, owner: github),
        name: "Verified Acme Actions 3",
      )
      make_searchable(github_action, type: "repository_action")

      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "repository-action")
      query.phrase = ""

      results = query.execute.results.map do |result|
        [result["_model"], result["_score"]]
      end.to_h

      # Make sure it's the models we expect
      assert_same_elements [
        @verified_repository_action,
        azure_action,
        github_action,
        @repository_action,
        @repository_org_action
      ], results.keys

      # Verified non-github/azure should have a higher score than azure/github
      assert_operator results[@verified_repository_action], :>, results[azure_action]

      # GitHub and Azure should have about the same score
      assert_in_delta results[github_action], results[azure_action], 0.0001

      # Make sure the unverified one is scored less than the github/azure ones
      assert_operator results[@repository_action], :<, results[github_action]
    ensure
      # We must delete these because they will pollute the index otherwise and be high ranking as they are verified.
      # The index is only setup and deleted one for this entire file, so we have to do this manually.
      RemoveFromSearchIndexJob.perform_now("repository_action", github_action.id)
      github_action.destroy!
      RemoveFromSearchIndexJob.perform_now("repository_action", azure_action.id)
      azure_action.destroy!
    end

    test "can query by category for repository action with feature flag enabled" do
      category = create(:marketplace_category, name: "chat")

      @repository_action.categories << category
      make_searchable(@repository_action, type: "repository_action")

      unlisted_action = create(:repository_action, state: :unlisted, categories: [category])
      make_searchable(unlisted_action, type: "repository_action")

      other_category = create(:marketplace_category)
      other_action = create(:repository_action, :listed, categories: [other_category])
      make_searchable(other_action, type: "repository_action")

      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "repository-action")
      query.phrase = "is:\"#{category.name}\""

      results = query.execute.results.map { |result| result["_model"] }
      assert_includes results, @repository_action
      refute_includes results, other_action
      refute_includes results, unlisted_action

      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "repository-action")
      query.phrase = "category:\"#{category.name}\""

      results = query.execute.results.map { |result| result["_model"] }
      assert_includes results, @repository_action
      refute_includes results, other_action
      refute_includes results, unlisted_action

      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "repository-action")
      mixed_case_category_name = category.name.scan(/.{1,2}/).map(&:capitalize).join
      query.phrase = mixed_case_category_name

      results = query.execute.results.map { |result| result["_model"] }
      assert_includes results, @repository_action
      refute_includes results, other_action
      refute_includes results, unlisted_action
    end

    test "sorting by an invalid parameter defaults to score sort" do
      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "repository-action")
      query.phrase = 'sort:"invalid_parameter"'

      scores = query.execute.results.map { |result| result["_score"] }

      assert_equal scores, scores.sort.reverse # default is desc order
    end

    context "publisher search" do
      test "query qualifiers include owner_login" do
        query = Search::Queries::MarketplaceQuery.new(current_user: @user, phrase: publisher_user_query, type: "marketplace-tools")

        assert query.qualifiers.include?(:"owner_login.raw")
      end

      test "apps and actions published by user are listed on publisher search by user login" do
        query = Search::Queries::MarketplaceQuery.new(current_user: @user, phrase: publisher_user_query, type: "marketplace-tools")

        results = query.execute.results.map { |result| result["_model"] }

        assert_equal results.count, 5
        assert_includes results, @marketplace_listing
        assert_includes results, @unverified_listing
        assert_includes results, @verification_pending_from_unverified_listing
        assert_includes results, @repository_action
      end

      test "apps and actions published by org are listed for publisher search by org login" do
        query = Search::Queries::MarketplaceQuery.new(current_user: @org.admin, phrase: publisher_org_query, type: "marketplace-tools")

        results = query.execute.results.map { |result| result["_model"] }

        assert_equal results.count, 4
        assert_includes results, @marketplace_org_listing
        assert_includes results, @unverified_org_listing
        assert_includes results, @verification_pending_from_unverified_org_listing
        assert_includes results, @repository_org_action
      end

      # the following 4 test cases ensure test completeness for case insensitivity during publisher search
      # case 1: lowercase search qualifier (publisher:testorg), lowercase publisher name (testorg)
      # case 2: lowercase search qualifier (publisher:testorg), uppercase publisher name (TestOrg)
      # case 3: uppercase search qualifier (publisher:TestOrg), lowercase publisher name (testorg)
      # case 4: uppercase search qualifier (publisher:TestOrg), uppercase publisher name (TestOrg)

      test "apps and actions are listed for publisher search when search qualifier is lowercase and publisher name is lowercase" do
        org = create(:organization, name: "testorg")
        marketplace_org_listing = create(:marketplace_listing, :verified, listable: create(:oauth_application, user: org))
        repository_org_action = create(:repository_action, :listed, repository: create(:repository, owner: org))

        make_searchable(marketplace_org_listing, type: "marketplace_listing")
        make_searchable(repository_org_action, type: "repository_action")

        query = Search::Queries::MarketplaceQuery.new(current_user: org.admin, phrase: "owner_login.raw:testorg", type: "marketplace-tools")

        results = query.execute.results.map { |result| result["_model"] }

        assert_equal results.count, 2
        assert_includes results, marketplace_org_listing
        assert_includes results, repository_org_action
      end

      test "apps and actions are listed for publisher search when search qualifier is lowercase and publisher name is uppercase" do
        org = create(:organization, name: "TestOrg")
        marketplace_org_listing = create(:marketplace_listing, :verified, listable: create(:oauth_application, user: org))
        repository_org_action = create(:repository_action, :listed, repository: create(:repository, owner: org))

        make_searchable(marketplace_org_listing, type: "marketplace_listing")
        make_searchable(repository_org_action, type: "repository_action")

        query = Search::Queries::MarketplaceQuery.new(current_user: org.admin, phrase: "owner_login.raw:testorg", type: "marketplace-tools")

        results = query.execute.results.map { |result| result["_model"] }

        assert_equal results.count, 2
        assert_includes results, marketplace_org_listing
        assert_includes results, repository_org_action
      end

      test "apps and actions are listed for publisher search when search qualifier is uppercase and publisher name is lowercase" do
        org = create(:organization, name: "testorg")
        marketplace_org_listing = create(:marketplace_listing, :verified, listable: create(:oauth_application, user: org))
        repository_org_action = create(:repository_action, :listed, repository: create(:repository, owner: org))

        make_searchable(marketplace_org_listing, type: "marketplace_listing")
        make_searchable(repository_org_action, type: "repository_action")

        query = Search::Queries::MarketplaceQuery.new(current_user: org.admin, phrase: "owner_login.raw:TestOrg", type: "marketplace-tools")

        results = query.execute.results.map { |result| result["_model"] }

        assert_equal results.count, 2
        assert_includes results, marketplace_org_listing
        assert_includes results, repository_org_action
      end

      test "apps and actions are listed for publisher search when search qualifier is uppercase and publisher name is uppercase" do
        org = create(:organization, name: "TestOrg")
        marketplace_org_listing = create(:marketplace_listing, :verified, listable: create(:oauth_application, user: org))
        repository_org_action = create(:repository_action, :listed, repository: create(:repository, owner: org))

        make_searchable(marketplace_org_listing, type: "marketplace_listing")
        make_searchable(repository_org_action, type: "repository_action")

        query = Search::Queries::MarketplaceQuery.new(current_user: org.admin, phrase: "owner_login.raw:TestOrg", type: "marketplace-tools")

        results = query.execute.results.map { |result| result["_model"] }

        assert_equal results.count, 2
        assert_includes results, marketplace_org_listing
        assert_includes results, repository_org_action
      end

      test "only apps published by user are listed for publisher search by user login and apps filter" do
        query = Search::Queries::MarketplaceQuery.new(current_user: @user, phrase: publisher_user_query, type: "marketplace")

        results = query.execute.results.map { |result| result["_model"] }

        assert_equal results.count, 4
        assert_includes results, @marketplace_listing
        assert_includes results, @unverified_listing
        assert_includes results, @verification_pending_from_unverified_listing
        refute_includes results, @repository_action
      end

      test "only actions published by org are listed for publisher search by org login and actions filter" do
        query = Search::Queries::MarketplaceQuery.new(current_user: @org.admin, phrase: publisher_org_query, type: "repository-action")

        results = query.execute.results.map { |result| result["_model"] }

        assert_equal results.count, 1
        refute_includes results, @marketplace_org_listing
        refute_includes results, @unverified_org_listing
        refute_includes results, @verification_pending_from_unverified_org_listing
        assert_includes results, @repository_org_action
      end

      test "apps and actions published by user and only matching search query are listed for publisher search by user login with search query" do
        query = Search::Queries::MarketplaceQuery.new(current_user: @user, phrase: publisher_user_query + " acm", type: "marketplace-tools")

        results = query.execute.results.map { |result| result["_model"] }

        assert_equal results.count, 3
        assert_includes results, @marketplace_listing
        assert_includes results, @unverified_listing
        assert_includes results, @repository_action
        refute_includes results, @verification_pending_from_unverified_listing
        refute_includes results, @marketplace_org_listing
      end

      test "actions and apps published by org belonging to a category are listed for publisher search by org login and category filter" do
        category = create(:marketplace_category, name: "chat")

        @marketplace_org_listing.categories << category
        make_searchable(@marketplace_org_listing, type: "marketplace_listing")

        @repository_org_action.categories << category
        make_searchable(@repository_org_action, type: "repository_action")

        @unverified_listing.categories << category
        make_searchable(@unverified_listing, type: "marketplace_listing")

        query = Search::Queries::MarketplaceQuery.new(current_user: @org.admin, phrase: publisher_org_query + " category:\"#{category.name}\"", type: "marketplace-tools")

        results = query.execute.results.map { |result| result["_model"] }

        assert_equal results.count, 2
        assert_includes results, @marketplace_org_listing
        assert_includes results, @repository_org_action
        refute_includes results, @unverified_org_listing
        refute_includes results, @verification_pending_from_unverified_org_listing
        refute_includes results, @unverified_listing
      end

      test "publisher search with login that owns no apps returns 0 results" do
        no_app_user = create(:user)
        query = Search::Queries::MarketplaceQuery.new(current_user: no_app_user, phrase: "owner_login:#{no_app_user.login}", type: "marketplace-tools")

        results = query.execute.results.map { |result| result["_model"] }

        assert_equal results.count, 0
      end

      test "publisher search with invalid login returns 0 results" do
        query = Search::Queries::MarketplaceQuery.new(current_user: @user, phrase: "owner_login:invalid-login", type: "marketplace-tools")

        results = query.execute.results.map { |result| result["_model"] }

        assert_equal results.count, 0
      end
    end

    context "when increase_actions_marketplace_visibility is enabled" do
      test "verified repository actions are boosted above non-verified actions if query is not blank" do
        query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "repository-action")
        query.phrase = "Acme"

        results = query.execute.results.map { |result| [result["_model"], result["_score"]] }.to_h
        assert_same_elements [@verified_repository_action, @repository_action], results.keys

        # Verified score will be greater than the non-verfied score
        assert_operator results[@verified_repository_action], :>, results[@repository_action]
      end

      test "verified partner repository actions are listed above unverified listings and non-verified actions" do
        azure = create(:organization, login: "Azure")
        github = create(:organization, login: "actions")

        azure_action = create(
          :repository_action,
          :verified,
          :listed,
          repository: create(:repository, owner: azure),
          name: "Verified Acme Actions 2",
        )
        make_searchable(azure_action, type: "repository_action")

        github_action = create(
          :repository_action,
          :verified,
          :listed,
          repository: create(:repository, owner: github),
          name: "Verified Acme Actions 3",
        )
        make_searchable(github_action, type: "repository_action")

        query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "repository-action")
        query.phrase = ""

        results = query.execute.results.map do |result|
          [result["_model"], result["_score"]]
        end.to_h

        # Make sure it's the models we expect
        assert_same_elements [
          @verified_repository_action,
          azure_action,
          github_action,
          @repository_action,
          @repository_org_action,
        ], results.keys

        # Make sure the unverified one is scored less than the github/azure ones
        assert_operator results[@repository_action], :<, results[github_action]
        assert_operator results[@repository_action], :<, results[azure_action]
      ensure
        # We must delete these because they will pollute the index otherwise and be high ranking as they are verified.
        # The index is only setup and deleted one for this entire file, so we have to do this manually.
        RemoveFromSearchIndexJob.perform_now("repository_action", github_action.id)
        github_action.destroy!
        RemoveFromSearchIndexJob.perform_now("repository_action", azure_action.id)
        azure_action.destroy!
      end
    end
  end

  context "when building the sort" do
    test "returns nil when the sort is empty and a query is present" do
      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "marketplace-tools")
      query.phrase = "foo"
      assert_nil query.build_sort
    end

    test "returns nil when the sort is dependents count and the ff is disabled" do
      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "marketplace-tools")
      query.sort = %w[dependents-count desc]
      assert_nil query.build_sort
    end

    test "maps the created sort field" do
      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "marketplace-tools")
      query.sort = %w[created desc]
      assert_equal([{ "created_at" => { "order" => "desc", "unmapped_type" => "date" } }], query.build_sort)
    end

    test "maps the popularity sort field to installation_count when searching for apps when the ff is turned on" do
      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "marketplace")
      query.sort = %w[popularity desc]
      assert_equal([{ "installation_count" => "desc" }], query.build_sort)
    end

    test "maps the monthly popularity sort field to installation_count_last_month when searching for apps when the ff is turned on" do
      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "marketplace")
      query.sort = %w[last-month-popularity desc]
      assert_equal([{ "installation_count_last_month" => "desc" }], query.build_sort)
    end

    test "maps the popularity sort field to stars when searching for actions when the ff is turned on" do
      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "repository-action")
      query.sort = %w[popularity desc]
      assert_equal([{ "stars" => "desc" }], query.build_sort)
    end

    test "maps the popularity sort field to _score when no type is provided when the ff is turned on" do
      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "marketplace-tools")
      query.sort = %w[popularity desc]
      assert_equal([{ "_score" => "desc" }], query.build_sort)
    end

    test "maps the dependents count sort field when the ff is turned on" do
      GitHub.flipper[:dependents_count_marketplace].enable @user
      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "marketplace-tools")
      query.sort = %w[dependents-count desc]
      assert_equal([{ "dependents_count" => { "order" => "desc", "unmapped_type" => "integer" } }], query.build_sort)
    end
  end

  context "pruning of search results" do
    test "repository_action with a disabled repo is removed from the search index" do
      new_user = create(:user)
      new_action = create(:repository_action, :listed, name: "Apple Action", repository: create(:repository, owner: new_user))
      make_searchable(new_action, type: "repository_action")

      repository_access = new_action.repository.access
      repository_access.disable(
        "size",
        @user,
        instructions: "instructions",
        disabling_detail: "details",
        )

      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "repository-action")
      results = query.execute.results.map { |result| result["_model"] }
      refute_includes results, new_action
    end

    test "marketplace listing whose integration has become private is removed from search index" do
      new_marketplace_listing = create(:marketplace_listing, :verified, name: "Acme Listing", listable: create(:integration, owner: @user))
      make_searchable(new_marketplace_listing, type: "marketplace_listing")

      new_marketplace_listing.listable.make_private

      query = Search::Queries::MarketplaceQuery.new(current_user: @user, type: "marketplace")
      results = query.execute.results.map { |result| result["_model"] }
      refute_includes results, new_marketplace_listing
    end
  end
end
