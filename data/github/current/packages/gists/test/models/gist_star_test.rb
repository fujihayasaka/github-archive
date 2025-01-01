# typed: true
# frozen_string_literal: true

require "test_helper"

class GistStarsTest < GitHub::TestCase
  include HydroTestHelpers

  def gist_test_content_array
    [
      { name: "1", value: "random content" },
    ]
  end

  fixtures do

    @user = create :user, email: "janedoe@example.com"
    @user2 = create :user, email: "johndoe@example.com"
    @spammer = create :user, spammy: true

    @gist = GistHelpers.generate contents: gist_test_content_array,
      user: @user,
      public: false
    @pub_gist = GistHelpers.generate contents: gist_test_content_array,
      user: @user,
      public: true
    @pub2_gist = GistHelpers.generate contents: gist_test_content_array,
      user: @user2,
      public: true
    @anon_gist = GistHelpers.generate contents: gist_test_content_array,
      public: true
    @spammy_gist = GistHelpers.generate contents: gist_test_content_array,
      user: @spammer,
      public: true
  end

  test "can star a gist" do
    refute Stars.domain.gist_starred_by_user?(@gist.id, @user.id)
    @user.star @gist

    assert Stars.domain.gist_starred_by_user?(@gist.id, @user.id)
  end

  test "can star an anonymous gist" do
    refute Stars.domain.gist_starred_by_user?(@anon_gist.id, @user.id)
    @user.star @anon_gist

    assert Stars.domain.gist_starred_by_user?(@anon_gist.id, @user.id)
  end

  context ".recently_starred_gists" do
    test "excludes private gists" do
      @user.star @gist
      @user.star @pub_gist

      assert starred_ids = GistStar.recently_starred_gists.pluck(:gist_id)
      refute_includes starred_ids, @gist.id
      assert_includes starred_ids, @pub_gist.id
    end

    if GitHub.spamminess_check_enabled?
      test "excludes spammy gists" do
        @user.star @spammy_gist
        @user.star @pub_gist

        assert starred_ids = GistStar.recently_starred_gists.pluck(:gist_id)
        refute_includes starred_ids, @spammy_gist.id
        assert_includes starred_ids, @pub_gist.id
      end
    end

    test "orders by most recently starred" do
      Timecop.freeze(30.minutes.ago) { @user.star @pub_gist }
      Timecop.freeze(20.minutes.ago) { @user.star @pub2_gist }
      Timecop.freeze(10.minutes.ago) { @user2.star @pub_gist }

      assert starred_ids = GistStar.recently_starred_gists.pluck(:gist_id)
      assert_equal [@pub_gist.id, @pub2_gist.id, @pub_gist.id], starred_ids
    end
  end

  context ".filter_spam_for" do
    test "excludes spammy gists", skip_if: :spamminess_check_enabled? do
      @spammer.star @pub_gist
      @user.star @pub_gist

      assert starred_ids = GistStar.filter_spam_for(@user2).pluck(:user_id)
      assert_includes starred_ids, @user.id
      if GitHub.spamminess_check_enabled?
        refute_includes starred_ids, @spammer.id
      else
        assert_includes starred_ids, @spammer.id
      end
    end

    test "shows spammy gists to admins", skip_if: :spamminess_check_enabled? do
      staff = create(:user, :staff)
      @spammer.star @pub_gist
      @user.star @pub_gist

      assert starred_ids = GistStar.filter_spam_for(staff).pluck(:user_id)
      assert_same_elements starred_ids, [@spammer.id, @user.id]
    end
  end

  context "hydro instrumentation" do
    test "has correct payload" do
      GitHub.stubs(:hydro_enabled?).returns(true)
      now = Time.now.beginning_of_day

      Timecop.freeze(now) do
        GitHub.context.push(actor_ip: "1.2.3.4")
        GitHub.context.push(user_agent: "test agent")

        owner = create(:user)
        starrer = create(:user)
        gist = GistHelpers.generate({
          contents: [{ name: "1", value: "random content" }],
          user: owner,
          public: true,
        })
        assert starrer.star(gist)
        star = GistStar.last
        refute_nil star

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(starrer),
          star_id: T.must(star).id,
          gist: Hydro::EntitySerializer.gist(gist),
          gist_owner: Hydro::EntitySerializer.user(owner),
          gist_stars_count: gist.stargazer_count,
          action_type: :STAR,
          context_type: :OTHER,
        }

        assert_hydro_published(message, schema: "github.v1.GistStar")
      end
    end
  end
end
