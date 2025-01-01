# typed: true
# frozen_string_literal: true

require "test_helper"

class GistAndRepositoryStarTest < GitHub::TestCase
  include HydroTestHelpers

  context "hydro instrumentation" do
    test "RepositoryStar has correct payload" do
      GitHub.stubs(:hydro_enabled?).returns(true)
      now = Time.now.beginning_of_day

      Timecop.freeze(now) do
        GitHub.context.push(actor_ip: "1.2.3.4")
        GitHub.context.push(user_agent: "test agent")

        owner = create(:user)
        starrer = create(:user)
        repo = create(:repository, owner: owner)

        starrer.star(repo)
        star = Star.last

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(starrer),
          star_id: T.must(star).id,
          repository: Hydro::EntitySerializer.repository(repo),
          repository_owner: Hydro::EntitySerializer.user(owner),
          repository_stars_count: repo.stargazer_count,
          action_type: :STAR,
          context_type: :OTHER,
          starred_at: T.must(star).created_at,
        }

        assert_hydro_published(message, schema: "github.v1.RepositoryStar")
      end
    end
  end
end
