# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectQueryParamTest < GitHub::TestCase
  test "it raises ArgumentError given a Repository and Organization that don't match" do
    repo = create(:repository)
    org = create(:organization)
    refute_equal org, repo.owner
    assert_raises ArgumentError do
      ProjectQueryParam.new(param: "boom", repository: repo, owner: org)
    end
  end

  test "it raises ArgumentError given a Repository and User that don't match" do
    repo = create(:repository)
    user = create(:organization)
    refute_equal user, repo.owner
    assert_raises ArgumentError do
      ProjectQueryParam.new(param: "boom", repository: repo, owner: user)
    end
  end

  context "valid?" do
    test "is true given an organization or user project param" do
      param = ProjectQueryParam.new(param: "org/123")
      assert param.valid?

      param = ProjectQueryParam.new(param: "o_r_g/123")
      assert param.valid?

      param = ProjectQueryParam.new(param: "o-r-g/123")
      assert param.valid?

      param = ProjectQueryParam.new(param: "0rg/123")
      assert param.valid?
    end

    test "is true given a repository project param" do
      param = ProjectQueryParam.new(param: "org/repo/123")
      assert param.valid?

      param = ProjectQueryParam.new(param: "org/-d4sh/123")
      assert param.valid?

      param = ProjectQueryParam.new(param: "org/.p1zza/123")
      assert param.valid?
    end

    test "is false given a param without a number" do
      param = ProjectQueryParam.new(param: "org/repo")
      refute param.valid?
    end

    test "is false given an invalid organization or user name" do
      param = ProjectQueryParam.new(param: "_org/repo/123")
      refute param.valid?

      param = ProjectQueryParam.new(param: "-org/repo/123")
      refute param.valid?
    end

    test "is false given an invalid repository name" do
      param = ProjectQueryParam.new(param: "org/%repo/123")
      refute param.valid?

      param = ProjectQueryParam.new(param: "org/&repo/123")
      refute param.valid?
    end

    test "is false given a random string" do
      param = ProjectQueryParam.new(param: "foobar")
      refute param.valid?
    end

    test "is false given an empty string" do
      param = ProjectQueryParam.new(param: "")
      refute param.valid?
    end

    test "is false given nil" do
      param = ProjectQueryParam.new(param: nil)
      refute param.valid?
    end

    context "given a Repository" do
      test "is true when the repo name and repo owner match" do
        repo = create(:repository)
        param = ProjectQueryParam.new(param: "#{repo.nwo}/123", repository: repo)
        assert param.valid?
      end

      test "is true when the repo owner matches" do
        repo = create(:repository)
        param = ProjectQueryParam.new(param: "#{repo.owner.login}/123", repository: repo)
        assert param.valid?
      end

      test "is false when the repo name doesn't match" do
        repo = create(:repository, name: "not-a-tacocat")
        param = ProjectQueryParam.new(param: "#{repo.owner.login}/#{repo.name.reverse}/123", repository: repo)
        refute param.valid?
      end

      test "is false when the owner login doesn't match" do
        repo = create(:repository, name: "not-a-tacocat")
        param = ProjectQueryParam.new(param: "#{repo.owner.login.reverse}/#{repo.name}/123", repository: repo)
        refute param.valid?
      end
    end

    context "given an Organization owner" do
      test "is true when the owner matches" do
        org = create(:organization)
        param = ProjectQueryParam.new(param: "#{org.login}/123", owner: org)
        assert param.valid?
      end

      test "is true when the repo owner matches" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        param = ProjectQueryParam.new(param: "#{repo.nwo}/123", owner: org)
        assert param.valid?
      end

      test "is false when the owner login doesn't match" do
        org = create(:organization, login: "slothette")
        param = ProjectQueryParam.new(param: "#{org.login.reverse}/123", owner: org)
        refute param.valid?
      end
    end

    context "given a User owner" do
      test "is true when the owner matches" do
        user = create(:user)
        param = ProjectQueryParam.new(param: "#{user.login}/123", owner: user)
        assert param.valid?
      end

      test "is true when the repo owner matches" do
        user = create(:user)
        repo = create(:repository, owner: user)
        param = ProjectQueryParam.new(param: "#{repo.nwo}/123", owner: user)
        assert param.valid?
      end

      test "is false when the owner login doesn't match" do
        user = create(:user, login: "slothette")
        param = ProjectQueryParam.new(param: "#{user.login.reverse}/123", owner: user)
        refute param.valid?
      end
    end

    context "given Repository and an Organization" do
      test "is true when the owner matches and repo is absent" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        param = ProjectQueryParam.new(param: "#{org.login}/123", owner: org, repository: repo)
        assert param.valid?
      end

      test "is true when the owner and repo name match" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        param = ProjectQueryParam.new(param: "#{repo.nwo}/123", owner: org, repository: repo)
        assert param.valid?
      end

      test "is false when the owner matches but repo name doesn't" do
        org = create(:organization)
        repo = create(:repository, owner: org, name: "weensy-burger")
        param = ProjectQueryParam.new(param: "#{org.login}/#{repo.name.reverse}/123", owner: org, repository: repo)
        refute param.valid?
      end

      test "is false when the repo name matches but owner doesn't" do
        org = create(:organization, name: "slothette")
        repo = create(:repository, owner: org)
        param = ProjectQueryParam.new(param: "#{org.login.reverse}/#{repo.name}/123", owner: org, repository: repo)
        refute param.valid?
      end
    end

    context "given Repository and a User" do
      test "is true when the owner matches and repo is absent" do
        user = create(:organization)
        repo = create(:repository, owner: user)
        param = ProjectQueryParam.new(param: "#{user.login}/123", owner: user, repository: repo)
        assert param.valid?
      end

      test "is true when the owner and repo name match" do
        user = create(:user)
        repo = create(:repository, owner: user)
        param = ProjectQueryParam.new(param: "#{repo.nwo}/123", owner: user, repository: repo)
        assert param.valid?
      end

      test "is false when the owner matches but repo name doesn't" do
        user = create(:user)
        repo = create(:repository, owner: user, name: "monster-cheese-wheel")
        param = ProjectQueryParam.new(param: "#{user.login}/#{repo.name.reverse}/123", owner: user, repository: repo)
        refute param.valid?
      end

      test "is false when the repo name matches but owner doesn't" do
        user = create(:user, name: "birb")
        repo = create(:repository, owner: user)
        param = ProjectQueryParam.new(param: "#{user.login.reverse}/#{repo.name}/123", owner: user, repository: repo)
        refute param.valid?
      end
    end
  end

  context "owner_login" do
    test "it returns the owner login from a valid param" do
      param = ProjectQueryParam.new(param: "org/123")
      assert_equal "org", param.owner_display_login
    end

    test "it returns the owner login from a valid param with a repo name" do
      param = ProjectQueryParam.new(param: "org/repo/123")
      assert_equal "org", param.owner_display_login
    end

    test "it is nil given an invalid param" do
      param = ProjectQueryParam.new(param: "org/repo")
      assert_nil param.owner_display_login
    end
  end

  context "repository_name" do
    test "it returns the repo name from a valid param" do
      param = ProjectQueryParam.new(param: "org/repo/123")
      assert_equal "repo", param.repository_name
    end

    test "it is nil given a valid param without a repo name" do
      param = ProjectQueryParam.new(param: "org/123")
      assert_nil param.repository_name
    end

    test "it is nil given an invalid param" do
      param = ProjectQueryParam.new(param: "org/repo")
      assert_nil param.repository_name
    end
  end

  context "number" do
    test "it is nil given a valid param without a repo name" do
      param = ProjectQueryParam.new(param: "org/123")
      assert_nil param.repository_name
    end

    test "it is nil given an invalid param" do
      param = ProjectQueryParam.new(param: "org/repo")
      assert_nil param.repository_name
    end
  end

  context "repository_project?" do
    test "is true when there is a repository name in the param" do
      param = ProjectQueryParam.new(param: "org/repo/123")
      assert param.repository_project?
    end

    test "is false when there is no repository name in the param" do
      param = ProjectQueryParam.new(param: "org/123")
      refute param.repository_project?
    end

    test "is false when there the param is invalid" do
      param = ProjectQueryParam.new(param: "foobar")
      refute param.repository_project?
    end
  end
end
