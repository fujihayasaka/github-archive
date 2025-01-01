# typed: true
# frozen_string_literal: true

require "test_helper"

class SpamSpammableTest < GitHub::TestCase
  fixtures do
    @admin = create(:verified_user)
    @org = create(:organization, admin: @admin)

    # Spammy user
    @spammy_user = create(:verified_user, spammy: true)
    @org.add_member(@spammy_user)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  if GitHub.spamminess_check_enabled?
    context "#hide_from_user?" do
      test "does not fail when the organization owner of a repository has been deleted" do
        spammy_org_member = create(:user)
        spammy_org = create(:organization, spammy: true).tap { |org| org.add_member(spammy_org_member) }
        spammy_org_repo = create(:repository, owner: spammy_org)
        spammy_org.delete

        hide_from_user = assert_nothing_raised do
          Repositories::Public.find_active!(spammy_org_repo.id).hide_from_user?(spammy_org_member)
        end

        assert hide_from_user
      end
    end

    # To be able to properly test the instrumentation within the Spam::Spammable module
    # we need persistence. The MemexProject model is used below as its one of the models
    # in the codebase that implements the Spam::Spammable module. MemexProject is not
    # necessary to be used exclusively in the Spam::Spammable module tests, but you're
    # welcome to continue testing against it.
    context "#instrument_user_hidden_change" do
      test "instruments metric on creation for content hidden to users" do
        assert_difference 'GitHub.dogstats.increments("spammable.user_hidden_changed").count', 1 do
          memex_project = create(:memex_project, owner: @org, title: "spam", creator: @spammy_user)
          assert_predicate memex_project, :user_hidden?
        end

        last_tags = GitHub.dogstats.increments("spammable.user_hidden_changed").last.tags

        assert_includes last_tags, "state:hidden"
        assert_includes last_tags, "model:MemexProject"
      end

      test "does not instrument metric on creation for content not hidden to users" do
        assert_no_difference 'GitHub.dogstats.increments("spammable.user_hidden_changed").count' do
          memex_project = create(:memex_project, owner: @org, creator: @admin)
          refute_predicate memex_project, :user_hidden?
        end
      end

      test "instruments metric on update for content that is hidden to users" do
        memex_project = assert_no_difference 'GitHub.dogstats.increments("spammable.user_hidden_changed").count' do
          create(:memex_project, owner: @org, title: "spam", creator: @admin).tap do |record|
            refute_predicate record, :user_hidden?
          end
        end

        @admin.mark_as_spammy
        assert_predicate @admin, :spammy?

        assert_difference 'GitHub.dogstats.increments("spammable.user_hidden_changed").count', 1 do
          memex_project.reload.save!
          assert_predicate memex_project, :user_hidden?
        end

        last_tags = GitHub.dogstats.increments("spammable.user_hidden_changed").last.tags

        assert_includes last_tags, "state:hidden"
        assert_includes last_tags, "model:MemexProject"
      end

      test "instrument visible state tag when user hidden flag is removed" do
        memex_project = create(:memex_project, owner: @org, title: "spam", creator: @spammy_user)
        assert_predicate memex_project, :user_hidden?

        @spammy_user.mark_not_spammy

        assert_difference 'GitHub.dogstats.increments("spammable.user_hidden_changed").count', 1 do
          memex_project.reload.save!
          refute_predicate memex_project, :user_hidden?
        end

        last_tags = GitHub.dogstats.increments("spammable.user_hidden_changed").last.tags

        assert_includes last_tags, "state:visible"
        assert_includes last_tags, "model:MemexProject"
      end

      test "does not instrument metric on delete for content hidden to users" do
        memex_project = create(:memex_project, owner: @org, title: "spam", creator: @spammy_user)
        assert_predicate memex_project, :user_hidden?

        assert_no_difference 'GitHub.dogstats.increments("spammable.user_hidden_changed").count' do
          memex_project.destroy!
        end
      end
    end
  end
end
