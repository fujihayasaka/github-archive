# typed: true
# frozen_string_literal: true

require "test_helper"

class StratocasterEventPrefillerTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @member = create(:user)
    @repo_member = create(:user)

    @org = create(:organization, admin: @user)

    @repo = create(:repository, owner: @org, from_example: :octolytics)
    @repo.add_member @repo_member

    @push1 = create(:push, repository: @repo, ref: "master", pusher: @user,
                       before: "3b63a02b13224e952b08fbbd7aa39d7232f0c1b0",
                       after: "f21cc854bd69168944ebf07bc26f4b1e9bef2037")
    @push2 = create(:push, repository: @repo, ref: "master", pusher: @repo_member,
                       before: "f21cc854bd69168944ebf07bc26f4b1e9bef2037",
                       after: "d3891ca7b2cb01a51bd1e36a6c32b4addfc94c28")
    @push3 = create(:push, repository: @repo, ref: "master", pusher: @member,
                       before: "d3891ca7b2cb01a51bd1e36a6c32b4addfc94c28",
                       after: "3e6a7829acab5cd256b404b8aeaf4dbe237851a0")
  end

  setup do
    GitHub.flipper[:preload_commits_with_enterprise].disable
  end

  test "can load multiple associations" do
    event = GitHub.stratocaster.build(repo: @repo, sender: @member)
    GitHub.stratocaster.create(event)

    event = GitHub.stratocaster.get(event.id)

    StratocasterEventPrefiller.new([event]).preload(:repos, :senders)

    assert_query_count(0) do
      assert_equal @repo, event.repo_record
      assert_equal @member, event.sender_record
    end
  end

  test "with enterprise managed users", skip_enterprise: true do
    GitHub.flipper[:preload_commits_with_enterprise].enable

    emu = create :emu, business: create(:business, :enterprise_managed, shortcode: "fab"), email: "emu-primary+fab@github.com", name: "emu-user"
    emu_business_org = create :enterprise_linked_organization,
                                business: emu.enterprise_managed_business,
                                admin: emu
    emu_business_org_repo = create :repository, owner: emu_business_org, from_example: :octolytics
    emu_business_org_repo2 = create :repository, owner: emu_business_org
    generic_user = create(:user, name: "generic-user", email: "emu-primary@github.com", login: "generic-user")

    push = create(:push, repository: emu_business_org_repo, ref: "master", pusher: generic_user,
                      before: "3b63a02b13224e952b08fbbd7aa39d7232f0c1b0",
                      after: "f21cc854bd69168944ebf07bc26f4b1e9bef2037")
    push2 = create(:push, repository: emu_business_org_repo2, ref: "master", pusher: generic_user,
                       before: "f21cc854bd69168944ebf07bc26f4b1e9bef2037",
                       after: "d3891ca7b2cb01a51bd1e36a6c32b4addfc94c28")

    event = GitHub.stratocaster.build(repo: emu_business_org_repo, event_type: "PushEvent", payload: {
      "commits" => [
        { "message" => "message3", "sha" => "sha3",
          "author" => { "email" => push.pusher.email, "name" => "name3" } },
      ],
    })
    event2 = GitHub.stratocaster.build(repo: emu_business_org_repo2, event_type: "PushEvent", payload: {
      "commits" => [
        { "message" => "message3", "sha" => "sha3",
          "author" => { "email" => push2.pusher.email, "name" => "name3" } },
      ],
    })
    event3 = GitHub.stratocaster.build(event_type: "PushEvent", payload: {
      "commits" => [
        { "message" => "message3", "sha" => "sha3",
          "author" => { "email" => @push1.pusher.email, "name" => "name3" } },
      ],
    })
    StratocasterEventPrefiller.new([event, event2, event3]).preload(:commit_authors)

    assert_equal emu, event.commit_author_for_email(push.pusher.email)
    assert_equal emu, event2.commit_author_for_email(push2.pusher.email)
    assert_equal @push1.pusher, event3.commit_author_for_email(@push1.pusher.email)
  end

  test "raises when unsupported association requested" do
    event = GitHub.stratocaster.build(repo: @repo, sender: @member)
    GitHub.stratocaster.create(event)

    event = GitHub.stratocaster.get(event.id)

    error = assert_raises { StratocasterEventPrefiller.new([event]).preload(:unknown, :senders, :foobar) }
    assert_equal "unknown is not a valid Stratocaster event association", error.message
  end

  context "preloading commit authors" do
    test "sets the commit authors for a push event" do
      event1 = GitHub.stratocaster.build(event_type: "PushEvent", payload: {
        "commits" => [
          { "message" => "message1", "sha" => "sha1",
            "author" => { "email" => @push1.pusher.email, "name" => "name1" } },
          { "message" => "message2", "sha" => "sha2",
            "author" => { "email" => @push2.pusher.email, "name" => "name2" } },
        ],
      })
      event2 = GitHub.stratocaster.build(event_type: "PushEvent", payload: {
        "commits" => [
          { "message" => "message3", "sha" => "sha3",
            "author" => { "email" => @push3.pusher.email, "name" => "name3" } },
        ],
      })

      assert_query_count(2) do # user_emails queries
        StratocasterEventPrefiller.new([event1, event2]).preload(:commit_authors)
      end

      assert_query_count(0) do
        assert_equal @push1.pusher, event1.commit_author_for_email(@push1.pusher.email)
        assert_equal @push2.pusher, event1.commit_author_for_email(@push2.pusher.email)
        assert_equal @push3.pusher, event2.commit_author_for_email(@push3.pusher.email)
      end
    end
  end

  context "preloading repositories" do
    test "sets the repo" do
      repo = { "id" => @repo.id }
      first_event = Stratocaster::Event.new(repo: repo)
      second_event = Stratocaster::Event.new(repo: repo)

      StratocasterEventPrefiller.new([first_event, second_event]).preload(:repos)

      assert_query_count(0) do
        assert_equal @repo, first_event.repo_record
        assert_equal @repo, second_event.repo_record
      end
    end

    test "loads the repo's primary language" do
      linguist_language = Linguist::Language.all.first
      language_name = LanguageName.create(name: linguist_language)
      @repo.update(primary_language: language_name)
      repo = { "id" => @repo.id }
      first_event = Stratocaster::Event.new(repo: repo)
      second_event = Stratocaster::Event.new(repo: repo)

      StratocasterEventPrefiller.new([first_event, second_event]).preload(:repos)

      assert_query_count(0) do
        assert_equal language_name, first_event.repo_record.primary_language
        assert_equal language_name, second_event.repo_record.primary_language
      end
    end

    test "sets the public attribute" do
      repo = { "id" => @repo.id }
      first_event = Stratocaster::Event.new(repo: repo)
      second_event = Stratocaster::Event.new(repo: repo)

      StratocasterEventPrefiller.new([first_event, second_event]).preload(:repos)

      assert_query_count(0) do
        assert_equal @repo.public?, first_event.public
        assert_equal @repo.public?, second_event.public
      end
    end

    test "sets the user" do
      repo = { "id" => @repo.id }
      first_event = Stratocaster::Event.new(repo: repo)
      second_event = Stratocaster::Event.new(repo: repo)
      user_attributes = { "id" => @repo.user.id, "login" => @repo.user.login, "display_login" => @repo.user.display_login, "gravatar_id" => "" }

      StratocasterEventPrefiller.new([first_event, second_event]).preload(:repos)

      assert_query_count(0) do
        assert_equal user_attributes, first_event.user
        assert_equal user_attributes, second_event.user
      end
    end

    test "sets organization when repo org is present" do
      repo = { "id" => @repo.id }
      repo_owner = @repo.owner
      first_event = Stratocaster::Event.new(repo: repo)
      second_event = Stratocaster::Event.new(repo: repo)

      StratocasterEventPrefiller.new([first_event, second_event]).preload(:repos)

      assert_query_count(0) do
        assert_equal repo_owner, first_event.org_record
        assert_equal repo_owner, second_event.org_record
      end
    end

    test "does not set organization when repo org is blank" do
      repo = { "id" => @repo.id }
      @repo.update(organization: nil)
      first_event = Stratocaster::Event.new(repo: repo)
      second_event = Stratocaster::Event.new(repo: repo)

      StratocasterEventPrefiller.new([first_event, second_event]).preload(:repos)

      assert_query_count(0) do
        assert_nil first_event.org_record
        assert_nil second_event.org_record
      end
    end

    test "does not set repo when repo is blank" do
      repo = { "id" => nil }
      first_event = Stratocaster::Event.new(repo: repo)
      second_event = Stratocaster::Event.new(repo: repo)

      StratocasterEventPrefiller.new([first_event, second_event]).preload(:repos)

      assert_query_count(0) do
        assert_nil first_event.repo_record
        assert_nil second_event.repo_record
      end
    end
  end

  context "preloading senders" do
    test "sets the sender" do
      event1 = GitHub.stratocaster.build(repo: @repo, sender: @member)
      GitHub.stratocaster.create(event1)
      event2 = GitHub.stratocaster.build(repo: @repo, sender: @user)
      GitHub.stratocaster.create(event2)

      event1 = GitHub.stratocaster.get(event1.id)
      event2 = GitHub.stratocaster.get(event2.id)

      assert_query_count(2) do # queries for users, profiles
        StratocasterEventPrefiller.new([event1, event2]).preload(:senders)
      end

      assert_query_count(0) do
        assert_equal @member, event1.sender_record
        assert_equal @user, event2.sender_record
      end
    end
  end
end
