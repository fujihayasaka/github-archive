# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotContentExclusionUrlNormalizer < GitHub::TestCase
  context "#normalize" do
    test "handles .git suffix" do
      result = Copilot::ContentExclusion::UrlNormalizer.new.normalize!("http://github.com/monalisa/smile.git/")
      assert_equal "monalisa/smile", result.path
      assert_equal "github.com", result.host
    end

    test "should raise if wildcard in host" do
      assert_raises(StandardError) do
        Copilot::ContentExclusion::UrlNormalizer.new.normalize!("http://*github.com/monalisa/smile")
      end
    end

    test "should raise more than one wildcard in path" do
      assert_raises(StandardError) do
        Copilot::ContentExclusion::UrlNormalizer.new.normalize!("http://github.com/*/*")
      end
    end

    [
      "git@github.com:monalisa/smile.git",
      "https://github.com/monalisa/smile",
      "ssh://git@github.com/monalisa/smile",
      "http://github.com/monalisa/smile.git/",
    ].each do |url|
      test "can parse '#{url}'" do
        result = Copilot::ContentExclusion::UrlNormalizer.new.normalize!(url)
        assert_equal "monalisa/smile", result.path
        assert_equal "github.com", result.host
      end
    end
  end

  context "#match" do
    [
      ["git@github.com:monalisa/smile.git", "https://github.com/monalisa/smile", true],
      ["ssh://git@github.com/monalisa/smile", "http://github.com/monalisa/smile.git/", true],
      ["ssh://git@github.com/monalisa/smile", "http://github.com/monalisa/frown.git/", false],
      ["git@github.com:monalisa/frown", "git@github.com:monalisa/frown", true],
      ["https://github.com/monalisa/smile", "git@github.com:monalisa/frown", false],
      ["jane@github.com:monalisa/smile", "john@github.com:monalisa/smile", true],
      ["jane@github.com:monalisa/*", "john@github.com:monalisa/smile", true],
      ["jane@github.com:*/frown", "john@github.com:monalisa/smile", false],
      ["jane@github.com:monalisa/smile", "John@github.com:MonaLisa/Smile", true],
      ["jane@github.com:*/smile", "john@github.com:monalisa/smile", true],
      ["git+ssh://jane@github.com/*/smile", "john@github.com:monalisa/smile", true],
      ["ssh+git://git@github.com/monalisa/smile", "https://github.com/monalisa/smile", true],
      ["*", "john@github.com:monalisa/smile", true],
      # AzuerDevOps specials
      ["git@ssh.dev.azure.com:v3/org/project/repo", "org@vs-ssh.visualstudio.com:v3/org/project/repo", true],
      ["git@dev.azure.com:v3/*/project/repo-name", "https://org.visualstudio.com/DefaultCollection/project/_git/repo-name", true],
      ["git@dev.azure.com:v3/org/*/repo-name", "https://org.visualstudio.com/DefaultCollection/project/_git/repo-name", true],
      ["git@dev.azure.com:v3/org/project/*", "https://org.visualstudio.com/another-org/_git/repo-name", false],
      ["git@dev.azure.com:v3/org/project/*", "https://org.visualstudio.com/DefaultCollection/project/_git/repo-name", true],
      ["git@ssh.dev.azure.com:v3/*/project/repo", "https://account.visualstudio.com/project/_git/_full/repo", true],
      ["git@ssh.dev.azure.com:v3/*/project/repo", "https://account.visualstudio.com/project/_git/repo", true],
      ["git@ssh.dev.azure.com:v3/*/project/repo", "https://org.visualstudio.com/DefaultCollection/project/_git/repo", true],
      ["git@ssh.dev.azure.com:v3/org/project/*", "git@ssh.dev.azure.com:v3/org/project/repo", true],
      ["git@ssh.dev.azure.com:v3/org/project/*", "https://org.visualstudio.com/DefaultCollection/project/_git/repo-name", true],
      ["git@ssh.dev.azure.com:v3/org/project/*", "https://org.visualstudio.com/DefaultCollection/project/_git/repo", true],
      ["git@ssh.dev.azure.com:v3/org/project/*", "https://org.visualstudio.com/project/_git/repo-name", true],
      ["git@ssh.dev.azure.com:v3/org/project/repo", "git@ssh.dev.azure.com:v2/org/project/repo", false],
      ["git@ssh.dev.azure.com:v3/org/project/repo", "git@ssh.dev.azure.com:v3/different-org/project/repo", false],
      ["git@ssh.dev.azure.com:v3/org/project/repo", "git@ssh.dev.azure.com:v3/org/different-project/repo", false],
      ["git@ssh.dev.azure.com:v3/org/project/repo", "git@ssh.dev.azure.com:v3/org/project/different-repo", false],
      ["git@ssh.dev.azure.com:v3/org/project/repo", "git@ssh.dev.azure.com:v3/org/project/repo-different", false],
      ["git@ssh.dev.azure.com:v3/org/project/repo", "git@ssh.dev.azure.com:v3/org/project/repo", true],
      ["git@ssh.dev.azure.com:v3/org/project/repo", "https://org.visualstudio.com/DefaultCollection/project/_git/_full/repo", true],
      ["git@ssh.dev.azure.com:v3/org/project/repo", "https://org.visualstudio.com/DefaultCollection/project/_git/repo", true],
      ["git@ssh.dev.azure.com:v3/org/project/repo*", "https://org.visualstudio.com/_git/project/repo-name", true],
      ["https://account.visualstudio.com/_git/abc", "https://dev.azure.com/account/_git/abc", true],
      ["https://org.visualstudio.com/DefaultCollection/*/_git/repo", "git@ssh.dev.azure.com:v3/org/project/repo", true],
      ["https://org.visualstudio.com/DefaultCollection/project/_git/_full/*", "git@vs-ssh.visualstudio.com:v3/org/project/repo-name", true],
      ["https://org.visualstudio.com/DefaultCollection/project/_git/_full/*", "https://dev.azure.com/org/project/_git/_full/repo-name", true],
      ["https://org.visualstudio.com/DefaultCollection/project/_git/_full/*", "https://org.visualstudio.com/DefaultCollection/project/_git/_optimized/repo-name", true],
      ["https://org.visualstudio.com/DefaultCollection/project/_git/_full/*", "https://org.visualstudio.com/DefaultCollection/project/_git/repo-name", true],
      ["https://org.visualstudio.com/DefaultCollection/project/_git/_full/repo-name", "git@ssh.dev.azure.com:v3/org/project/repo", false],
      ["https://org.visualstudio.com/DefaultCollection/project/_git/_full/repo-name", "git@vs-ssh.visualstudio.com:v3/org/project/repo-name", true],
      ["https://org.visualstudio.com/DefaultCollection/project/_git/_full/repo-name", "https://dev.azure.com/org/project/_git/_full/repo-name", true],
      ["https://org.visualstudio.com/DefaultCollection/project/_git/_full/repo-name", "https://org.visualstudio.com/DefaultCollection/project/_git/_optimized/repo-name", true],
      ["https://org.visualstudio.com/DefaultCollection/project/_git/_full/repo-name", "https://org.visualstudio.com/DefaultCollection/project/_git/repo-name", true],
      ["https://org.visualstudio.com/DefaultCollection/project/_git/repo-name", "git@ssh.dev.azure.com:v3/org/project/repo", false],
      ["https://org.visualstudio.com/DefaultCollection/project/_git/repo-name", "https://dev.azure.com/org/project/_git/repo-name", true],
      ["https://org.visualstudio.com/DefaultCollection/project/_git/repo-name", "https://different-org.visualstudio.com/DefaultCollection/project/_git/repo-name", false],
      ["https://org.visualstudio.com/DefaultCollection/project/_git/repo-name", "https://org.visualstudio.com/DefaultCollection/different-project/_git/repo-name", false],
      ["https://org.visualstudio.com/DefaultCollection/project/_git/repo-name", "https://org.visualstudio.com/DefaultCollection/project/_git/_optimized/repo-name", true],
      ["https://org.visualstudio.com/DefaultCollection/project/_git/repo-name", "https://org.visualstudio.com/DefaultCollection/project/_git/repo-name-different", false],
      ["https://org.visualstudio.com/DefaultCollection/project/_git/repo-name", "https://org.visualstudio.com/DefaultCollection/project/_git/repo-name?query=param", true],
      ["https://org.visualstudio.com/DefaultCollection/project/_git/repo-name", "https://org.visualstudio.com/DefaultCollection/project/_git/repo-name", true],
      ["https://org.visualstudio.com/DefaultCollection/project/_git/repo-name", "https://org.visualstudio.com/DefaultCollection/project/_git/repo-name/extra-path", false],
      ["https://org.visualstudio.com/DefaultCollection/project/_git/repo-name", "https://org.visualstudio.com/DefaultCollection/project/_git/repo-name#fragment", true],
      ["https://org.visualstudio.com/DefaultCollection/project/_git/repo-name", "https://org.visualstudio.com/DefaultCollection/project/_git/repo", false],
    ].each do |a, b, expected|
      test "match?('#{a}', '#{b}') == #{expected}" do
        equality = Copilot::ContentExclusion::UrlNormalizer.new.match?(a, b)
        assert_equal expected, equality, "expecting '#{a}' and '#{b}' to be #{expected ? "equal" : "not equal"}"
      end
    end

    test "matches for bitbucket" do
      assert Copilot::ContentExclusion::UrlNormalizer.new.match?("https://username@bitbucket.org/teamsinspace/documentation-tests.git", "git@bitbucket.org:teamsinspace/documentation-tests.git")
    end

    test "matches for gitlab" do
      assert Copilot::ContentExclusion::UrlNormalizer.new.match?("git@gitlab.com:gitlab-tests/sample-project.git", "https://gitlab.com/gitlab-tests/sample-project.git")
    end
  end
end
