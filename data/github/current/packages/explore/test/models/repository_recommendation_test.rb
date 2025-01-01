# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryRecommendationTest < GitHub::TestCase
  setup do
    @user = create(:user)
    @staff = create(:staff_admin_user)
    @repo1 = create(:repository, name: "rec-repo-1")
    @repo2 = create(:repository, name: "rec-repo-2")
    @repo3 = create(:repository, name: "rec-repo-3")

    # Star repositories so they'll be trending
    Timecop.freeze(1.year.ago) { create(:user).star(@repo1) }
    Timecop.freeze(1.month.ago) { create(:user).star(@repo2) }
    Timecop.freeze(1.day.ago) { create(:user).star(@repo3) }
  end

  context "#generated_at" do
    test "returns a datetime when field is present" do
      timestamp = 1502671892
      recommendation = RepositoryRecommendation.new(repository: @repo1, generated_at: timestamp)

      assert_equal Time.at(timestamp).to_datetime, recommendation.generated_at
    end

    test "returns nil when field is not present" do
      recommendation = RepositoryRecommendation.new(repository: @repo1, generated_at: nil)

      assert_nil recommendation.generated_at
    end
  end

  context "#can_be_recommended?" do
    test "returns true if repo is public and not opted out", skip_enterprise: true do
      recommendation = RepositoryRecommendation.new(repository: @repo1)
      assert_predicate recommendation, :can_be_recommended?
    end

    test "returns false for public repo that has been hidden from discovery" do
      @repo1.set_content_warning("violent_content", actor: @staff)
      recommendation = RepositoryRecommendation.new(repository: @repo1)
      refute_predicate recommendation, :can_be_recommended?
    end

    test "returns false for public repo that has a banner content warning" do
      @repo1.set_content_warning("student_pages", actor: @staff)
      recommendation = RepositoryRecommendation.new(repository: @repo1)
      refute_predicate recommendation, :can_be_recommended?
    end

    test "returns false for public repo that has an interstitial content warning" do
      @repo1.set_network_privilege(:hide_from_discovery, true)
      recommendation = RepositoryRecommendation.new(repository: @repo1)
      refute_predicate recommendation, :can_be_recommended?
    end

    if GitHub.enterprise?
      test "returns false for public repo not opted out, on Enterprise" do
        recommendation = RepositoryRecommendation.new(repository: @repo1)
        refute_predicate recommendation, :can_be_recommended?
      end
    end

    if GitHub.spamminess_check_enabled?
      test "returns false for repo owned by spammy user" do
        spammy_user = create(:user, spammy: true)
        spammy_repo = create(:repository, owner: spammy_user)
        recommendation = RepositoryRecommendation.new(repository: spammy_repo)
        refute_predicate recommendation, :can_be_recommended?
      end
    end

    test "returns false if repo is private" do
      private_repo = create(:private_repository)
      recommendation = RepositoryRecommendation.new(repository: private_repo)
      refute_predicate recommendation, :can_be_recommended?
    end

    test "returns false if repo is archived" do
      repo = create(:repository, maintained: false)
      recommendation = RepositoryRecommendation.new(repository: repo)
      refute_predicate recommendation, :can_be_recommended?
    end

    test "returns false if repo has been opted out" do
      RepositoryRecommendationOptOut.create(repository_id: @repo1.id)
      recommendation = RepositoryRecommendation.new(repository: @repo1)
      refute_predicate recommendation, :can_be_recommended?
    end
  end

  context "#can_opt_in?" do
    test "returns true if repo is public and opted out", skip_enterprise: true do
      RepositoryRecommendationOptOut.create(repository_id: @repo1.id)
      recommendation = RepositoryRecommendation.new(repository: @repo1)
      assert_predicate recommendation, :can_opt_in?
    end

    test "returns false for opted-out public repo that has been hidden from discovery" do
      RepositoryRecommendationOptOut.create(repository_id: @repo1.id)
      @repo1.set_network_privilege(:hide_from_discovery, true)
      recommendation = RepositoryRecommendation.new(repository: @repo1)
      refute_predicate recommendation, :can_opt_in?
    end

    if GitHub.enterprise?
      test "returns false for opted-out public repo on Enterprise" do
        RepositoryRecommendationOptOut.create(repository_id: @repo1.id)
        recommendation = RepositoryRecommendation.new(repository: @repo1)
        refute_predicate recommendation, :can_opt_in?
      end
    end

    if GitHub.spamminess_check_enabled?
      test "returns false for opted-out repo owned by spammy user" do
        RepositoryRecommendationOptOut.create(repository_id: @repo1.id)
        spammy_user = create(:user, spammy: true)
        spammy_repo = create(:repository, owner: spammy_user)
        recommendation = RepositoryRecommendation.new(repository: spammy_repo)
        refute_predicate recommendation, :can_opt_in?
      end
    end

    test "returns false if opted-out repo is private" do
      RepositoryRecommendationOptOut.create(repository_id: @repo1.id)
      private_repo = create(:private_repository)
      recommendation = RepositoryRecommendation.new(repository: private_repo)
      refute_predicate recommendation, :can_opt_in?
    end

    test "returns false if opted-out repo is archived" do
      RepositoryRecommendationOptOut.create(repository_id: @repo1.id)
      repo = create(:repository, maintained: false)
      recommendation = RepositoryRecommendation.new(repository: repo)
      refute_predicate recommendation, :can_opt_in?
    end

    test "returns false if repo has been not been opted out" do
      recommendation = RepositoryRecommendation.new(repository: @repo1)
      refute_predicate recommendation, :can_opt_in?
    end
  end

  context "#explain" do
    test "returns a sentence fragment for each possible reason" do
      repository = create :repository

      other = T.must(Platform::Enums::RepositoryRecommendationReason.values["OTHER"]).value
      fallback = "This repository might interest you"

      RepositoryRecommendation.valid_reasons.each do |reason|
        recommendation = RepositoryRecommendation.new(
          repository: repository, reason: reason)

        if reason == other
          assert_equal fallback, recommendation.explain
        else
          refute_equal fallback, recommendation.explain,
            "fallback explanation encountered for reason #{reason.inspect}"
        end
      end
    end
  end

  context "#opt_in" do
    test "returns true if the given repository has not been opted out" do
      assert RepositoryRecommendation.new(repository: @repo1).opt_in(actor: @staff)
    end

    test "returns false if the opt-out fails to be deleted" do
      RepositoryRecommendationOptOut.create(repository_id: @repo1.id)
      RepositoryRecommendationOptOut.any_instance.stubs(:destroy).returns(false)

      refute RepositoryRecommendation.new(repository: @repo1).opt_in(actor: @staff)
    end

    test "logs an audit log event" do
      RepositoryRecommendationOptOut.create(repository_id: @repo1.id)
      events = subscribe("repo.opt_into_recommendations")
      expected_payload = {
        visibility: :public,
        repo: @repo1.name_with_owner,
        repo_id: @repo1.id,
        public_repo: @repo1.public?,
        user: @repo1.owner.login,
        user_id: @repo1.owner_id,
        fork_source: @repo1.name_with_owner,
        fork_source_id: @repo1.id,
        actor: @staff.login,
        actor_id: @staff.id,
      }

      RepositoryRecommendation.new(repository: @repo1).opt_in(actor: @staff)

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context "#opt_out" do
    test "opts out the repository if it has not been already opted out" do
      assert_difference "RepositoryRecommendationOptOut.count" do
        RepositoryRecommendation.new(repository: @repo1).opt_out(actor: @staff)
      end
    end

    test "does not create a new record if repository has already been opted out" do
      RepositoryRecommendationOptOut.create(repository_id: @repo2.id)

      assert_no_difference "RepositoryRecommendationOptOut.count" do
        RepositoryRecommendation.new(repository: @repo2).opt_out(actor: @staff)
      end
    end

    test "logs an audit log event" do
      events = subscribe("repo.opt_out_of_recommendations")
      expected_payload = {
        visibility: :public,
        repo: @repo1.name_with_owner,
        repo_id: @repo1.id,
        public_repo: @repo1.public?,
        user: @repo1.owner.login,
        user_id: @repo1.owner_id,
        fork_source: @repo1.name_with_owner,
        fork_source_id: @repo1.id,
        actor: @staff.login,
        actor_id: @staff.id,
      }

      RepositoryRecommendation.new(repository: @repo1).opt_out(actor: @staff)

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context ".recommendations_from_json" do
    test "converts given hash to a list of recommendations" do
      json_str = %Q({
        "user_id": #{@user.id},
        "recommendations": [
          {
            "algorithm_version": "v1",
            "generated_at": 1502671892,
            "repository_id": #{@repo1.id},
            "score": 0.6,
            "reason": "popular",
            "public": true
          },
          {
            "algorithm_version": "v1",
            "generated_at": 1502671892,
            "repository_id": #{@repo2.id},
            "score": 0.5,
            "reason": "trending",
            "public": true
          }
        ]
      })
      hash = JSON.parse(json_str)

      result = RepositoryRecommendation.recommendations_from_json(@user, hash)

      assert_equal 2, result.size
      assert_equal "popular", result.first.reason
      assert_equal @repo1, result.first.repository
      assert_equal 0.6, result.first.score
      assert_equal "trending", result.last.reason
      assert_equal @repo2, result.last.repository
      assert_equal 0.5, result.last.score
    end
  end

  context ".filter" do
    test "doesn't make N+1 queries with org-owned repos" do
      repos = create_pair(:repository, :org_owned)
      # reset memoized @archived ivar to expose N+1s from #archived?
      repos.each(&:reload)
      recs = repos.map { |r| RepositoryRecommendation.new(repository: r) }

      query_counts = {
        users: 1, #Repository#archived?
        trade_controls_restrictions: 1, #Repository#archived?
      }
      assert_query_count_per_table(query_counts) do
        RepositoryRecommendation.filter(recs, user: @user)
      end
    end

    test "removes recommendations for repositories marked collaborators only" do
      collab_only_repo = create(:repository)
      create(:stafftools_network_privilege, repository: collab_only_repo, require_login: false,
                                        collaborators_only: true)
      recs = [RepositoryRecommendation.new(repository: collab_only_repo)]

      result = RepositoryRecommendation.filter(recs, user: @user)

      assert_empty result
    end

    test "removes recommendations for nonexistent repositories" do
      recommendations = [
        RepositoryRecommendation.new(repository: nil, reason: "TRENDING", score: 0.3,
                                     algorithm_version: "v1", generated_at: 1502671892),
      ]

      assert_empty RepositoryRecommendation.filter(recommendations, user: @user)
    end

    test "removes recommendations for public repositories requiring viewers be logged in" do
      require_login_repo = create(:repository)
      create(:stafftools_network_privilege, repository: require_login_repo, require_login: true,
                                        collaborators_only: false)
      recs = [RepositoryRecommendation.new(repository: require_login_repo)]

      result = RepositoryRecommendation.filter(recs, user: @user)

      assert_empty result
    end

    test "removes recommendations for public repositories that are marked as hide_from_discovery" do
      repo = create(:repository)
      repo.set_network_privilege(:hide_from_discovery, true)
      result = RepositoryRecommendation.filter([RepositoryRecommendation.new(repository: repo)], user: @user)
      assert_empty result
    end

    test "removes duplicate recommendations" do
      recs = [
        RepositoryRecommendation.new(repository: @repo1),
        RepositoryRecommendation.new(repository: @repo1),
      ]
      result = RepositoryRecommendation.filter(recs, user: @user)

      assert_equal 1, result.size
      assert_equal @repo1, result.first.repository
    end

    if GitHub.spamminess_check_enabled?
      test "removes recommendations for spammy repositories" do
        spammer = create(:user, spammy: true)
        spammy_repo = create(:repository, owner: spammer)
        recs = [RepositoryRecommendation.new(repository: spammy_repo)]

        result = RepositoryRecommendation.filter(recs, user: @user)

        assert_empty result
      end
    end

    test "removes recommendations for private repositories" do
      private_repo = create(:private_repository)
      recs = [RepositoryRecommendation.new(repository: private_repo)]

      result = RepositoryRecommendation.filter(recs, user: @user)

      assert_empty result
    end

    test "removes recommendations for opted-out repositories" do
      RepositoryRecommendationOptOut.create(repository_id: @repo1.id)
      recs = [RepositoryRecommendation.new(repository: @repo1)]

      result = RepositoryRecommendation.filter(recs, user: @user)

      assert_empty result
    end

    test "removes recommendations for repos starred by user" do
      repo = create(:repository)
      @user.star(repo)
      recs = [RepositoryRecommendation.new(repository: repo)]

      result = RepositoryRecommendation.filter(recs, user: @user)

      assert_empty result
    end

    test "removes recommendations for archived repos" do
      repo = create(:repository, maintained: false)
      recs = [RepositoryRecommendation.new(repository: repo)]

      result = RepositoryRecommendation.filter(recs, user: @user)

      assert_empty result
    end

    test "sorts by mobile order" do
      org = create(:organization)
      org_image = create(:repository_image)
      org_img_repo = create(:repository, open_graph_image: org_image, owner: org, name: "org_img")
      org_repo = create(:repository, owner: org, name: "org")

      image = create(:repository_image)
      user_img_repo = create(:repository, open_graph_image: image, owner: @user, name: "user_img")

      result = RepositoryRecommendation.filter(
        [
          RepositoryRecommendation.new(repository: @repo1),
          RepositoryRecommendation.new(repository: org_repo),
          RepositoryRecommendation.new(repository: org_img_repo),
          RepositoryRecommendation.new(repository: user_img_repo),
        ],
        user: @user,
        mobile_sort_order: true
      )

      expected = [org_img_repo, user_img_repo, org_repo, @repo1]

      result.each_with_index do |rec, idx|
        assert_equal expected[idx], rec.repository
      end
    end
  end

  context ".unfiltered_for" do
    if GitHub.munger_available?
      context "when munger returns less than the desired amount of recommendations" do
        test "returns recommendations from munger with proper num of fallback recommendations" do
          desired_results = 3
          Repository.stubs(per_page: desired_results)
          recs = [
            RepositoryRecommendation.new(repository: @repo1, reason: "popular", score: 0.3),
            RepositoryRecommendation.new(repository: @repo2, reason: "starred", score: 0.2)
          ]
          fallback_rec = RepositoryRecommendation.new(
            repository: build(:repository),
            reason: "popular",
            score: 1,
          )
          GitHub.munger.stubs(:repository_recommendations)
            .with(
              @user,
              page: 1,
              per_page: Repository.per_page,
            )
            .returns(recs)
          GitHub.munger.stubs(:repository_recommendations)
            .with(
              @user,
              page: 1,
              per_page: 1,
              fallback: true,
            )
            .returns([fallback_rec])

          results = RepositoryRecommendation.unfiltered_for(@user)

          assert_same_elements(recs + [fallback_rec], results)
        end

        test "returns all fallback recommendations if munger returns none" do
          fallback_recs = [
            RepositoryRecommendation.new(repository: @repo1, reason: "popular", score: 1),
            RepositoryRecommendation.new(repository: @repo2, reason: "popular", score: 0.2)
          ]

          GitHub.munger.stubs(:repository_recommendations)
            .with(@user, page: 1, per_page: 3)
            .returns([])
          GitHub.munger.stubs(:repository_recommendations)
            .with(@user, page: 1, per_page: 3, fallback: true)
            .returns(fallback_recs)

          results = RepositoryRecommendation.unfiltered_for(@user, per_page: 3)

          assert_same_elements(fallback_recs, results)
        end
      end

      context "when munger returns the desired amount of recommendations" do
        test "returns recommendations from munger" do
          recs = [
            RepositoryRecommendation.new(repository: @repo1, reason: "popular", score: 0.3),
            RepositoryRecommendation.new(repository: @repo2, reason: "starred", score: 0.2)
          ]
          GitHub.munger.stubs(:repository_recommendations)
            .with(
              @user,
              page: 1,
              per_page: Repository.per_page,
            )
            .returns(recs)
          GitHub.munger.stubs(:repository_recommendations)
            .with(
              @user,
              page: 1,
              per_page: Repository.per_page - recs.size,
              fallback: true
            )
            .returns([])

          assert_equal recs, RepositoryRecommendation.unfiltered_for(@user, page: 1)
        end
      end

      test "returns an empty array when Munger is down" do
        GitHub.munger.stubs(:repository_recommendations)
          .with(@user, page: 1, per_page: 10)
          .returns(nil)
        expected = []

        assert_equal expected, RepositoryRecommendation.unfiltered_for(@user, page: 1, per_page: 10)
      end
    else
      test "returns trending repositories" do
        expected = [
          RepositoryRecommendation.new(repository: @repo3, reason: "trending", score: 0),
          RepositoryRecommendation.new(repository: @repo2, reason: "trending", score: 0),
          RepositoryRecommendation.new(repository: @repo1, reason: "trending", score: 0),
        ]

        assert_equal expected, RepositoryRecommendation.unfiltered_for(@user, page: 1)
      end

      test "paginates trending repositories" do
        expected = [
          RepositoryRecommendation.new(repository: @repo1, reason: "trending", score: 0),
        ]

        assert_equal expected, RepositoryRecommendation.unfiltered_for(@user, page: 3, per_page: 1)
      end
    end
  end

  context ".filtered_for" do
    if GitHub.munger_available?
      test "returns recommendations from munger, filtered" do
        recs = [
          RepositoryRecommendation.new(repository: @repo1, reason: "popular", score: 0.2),
          RepositoryRecommendation.new(repository: @repo2, reason: "starred", score: 0.3),
          RepositoryRecommendation.new(repository: nil, reason: "trending", score: 0.4),
          RepositoryRecommendation.new(repository: @repo1, reason: "followed", score: 0.5),
        ]
        GitHub.munger.stubs(:repository_recommendations)
          .with(@user, page: 1, per_page: 30)
          .returns(recs)
        GitHub.munger.stubs(:repository_recommendations)
          .with(
            @user,
            page: 1,
            per_page: Repository.per_page - recs.size,
            fallback: true,
          )
          .returns([])

        assert_equal recs.first(2), RepositoryRecommendation.filtered_for(@user)
      end
    else
      test "returns trending repositories, filtered" do
        @repo2.destroy!

        expected = [
          RepositoryRecommendation.new(repository: @repo3, reason: "trending", score: 0),
          RepositoryRecommendation.new(repository: @repo1, reason: "trending", score: 0),
        ]

        assert_equal expected, RepositoryRecommendation.filtered_for(@user)
      end
    end
  end
end
