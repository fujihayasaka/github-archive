# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCampaigns
  class AutofixApplyHelperTest < GitHub::TestCase
    fixtures do
      @user = create(:user)
      @repository = create(:private_repository, from_example: :security_campaigns_autofixes, owner: @user)
    end

    def setup
      @helper = FakeHelper.new.extend(AutofixApplyHelper)

      @different_fixes = [
        {
          files: {
            "app2/index.js" => "--- a/app2/index.js\n+++ b/app2/index.js\n@@ -1,8 +1,9 @@\n const express = require(\"express\");\n+const escape = require('escape-html');\n \n const app = express();\n-app.get(\"/\", (req, res) => res.send(`Hello, ${req.query.name}!`));\n+app.get(\"/\", (req, res) => res.send(`Hello, ${escape(req.query.name)}!`));\n \n-app.get(\"/page2\", (req, res) => res.send(`Welcome to page 2, ${req.query.name}!`));\n+app.get(\"/page2\", (req, res) => res.send(`Welcome to page 2, ${escape(req.query.name)}!`));\n \n-app.get(\"/page4\", (req, res) => res.send(`Welcome to page 4, ${req.query.name}!`));\n+app.get(\"/page4\", (req, res) => res.send(`Welcome to page 4, ${escape(req.query.name)}!`));\n",
            "app2/package.json" => "--- a/app2/package.json\n+++ b/app2/package.json\n@@ -5,3 +5,4 @@\n     \"express\": \"^4.19.2\",\n-    \"rimraf\": \"^5.0.7\"\n+    \"rimraf\": \"^5.0.7\",\n+    \"escape-html\": \"^1.0.3\"\n   }\n",
          }
        },
        {
          files: {
            "app1/index.js" => "--- a/app1/index.js\n+++ b/app1/index.js\n@@ -1,2 +1,3 @@\n const express = require(\"express\");\n+const escape = require('escape-html');\n const {page6, page7} = require('./routes')\n@@ -4,7 +5,7 @@\n const app = express();\n-app.get(\"/\", (req, res) => res.send(`Hello, ${req.query.name}!`));\n+app.get(\"/\", (req, res) => res.send(`Hello, ${escape(req.query.name)}!`));\n \n-app.get(\"/page2\", (req, res) => res.send(`Welcome to page 2, ${req.query.name}!`));\n+app.get(\"/page2\", (req, res) => res.send(`Welcome to page 2, ${escape(req.query.name)}!`));\n \n-app.get(\"/page4\", (req, res) => res.send(`Welcome to page 4, ${req.query.name}!`));\n+app.get(\"/page4\", (req, res) => res.send(`Welcome to page 4, ${escape(req.query.name)}!`));\n \n",
            "app1/package.json" => "--- a/app1/package.json\n+++ b/app1/package.json\n@@ -3,3 +3,4 @@\n   \"dependencies\": {\n-    \"express\": \"^4.19.2\"\n+    \"express\": \"^4.19.2\",\n+    \"escape-html\": \"^1.0.3\"\n   }\n",
          }
        },
      ]
      @different_proposed_commits = create_proposed_commits(@different_fixes)

      @same_content_fixes = [
        {
          files: {
            "app2/index.js" => "--- a/app2/index.js\n+++ b/app2/index.js\n@@ -1,8 +1,9 @@\n const express = require(\"express\");\n+const escape = require('escape-html');\n \n const app = express();\n-app.get(\"/\", (req, res) => res.send(`Hello, ${req.query.name}!`));\n+app.get(\"/\", (req, res) => res.send(`Hello, ${escape(req.query.name)}!`));\n \n-app.get(\"/page2\", (req, res) => res.send(`Welcome to page 2, ${req.query.name}!`));\n+app.get(\"/page2\", (req, res) => res.send(`Welcome to page 2, ${escape(req.query.name)}!`));\n \n-app.get(\"/page4\", (req, res) => res.send(`Welcome to page 4, ${req.query.name}!`));\n+app.get(\"/page4\", (req, res) => res.send(`Welcome to page 4, ${escape(req.query.name)}!`));\n",
            "app2/package.json" => "--- a/app2/package.json\n+++ b/app2/package.json\n@@ -5,3 +5,4 @@\n     \"express\": \"^4.19.2\",\n-    \"rimraf\": \"^5.0.7\"\n+    \"rimraf\": \"^5.0.7\",\n+    \"escape-html\": \"^1.0.3\"\n   }\n",
          }
        },
        {
          files: {
            "app1/index.js" => "--- a/app1/index.js\n+++ b/app1/index.js\n@@ -1,2 +1,3 @@\n const express = require(\"express\");\n+const escape = require('escape-html');\n const {page6, page7} = require('./routes')\n@@ -4,7 +5,7 @@\n const app = express();\n-app.get(\"/\", (req, res) => res.send(`Hello, ${req.query.name}!`));\n+app.get(\"/\", (req, res) => res.send(`Hello, ${escape(req.query.name)}!`));\n \n-app.get(\"/page2\", (req, res) => res.send(`Welcome to page 2, ${req.query.name}!`));\n+app.get(\"/page2\", (req, res) => res.send(`Welcome to page 2, ${escape(req.query.name)}!`));\n \n-app.get(\"/page4\", (req, res) => res.send(`Welcome to page 4, ${req.query.name}!`));\n+app.get(\"/page4\", (req, res) => res.send(`Welcome to page 4, ${escape(req.query.name)}!`));\n \n",
            "app1/package.json" => "--- a/app1/package.json\n+++ b/app1/package.json\n@@ -3,3 +3,4 @@\n   \"dependencies\": {\n-    \"express\": \"^4.19.2\"\n+    \"express\": \"^4.19.2\",\n+    \"escape-html\": \"^1.0.3\"\n   }\n",
          }
        },
        {
          files: {
            "app1/routes.js" => "--- a/app1/routes.js\n+++ b/app1/routes.js\n@@ -1,2 +1,4 @@\n-export const page6 = (req, res) => res.send(`Welcome to page 6, ${req.query.name}!`);\n-export const page7 = (req, res) => res.send(`Welcome to page 7, ${req.query.name}!`);\n+import escape from 'escape-html';\n+\n+export const page6 = (req, res) => res.send(`Welcome to page 6, ${escape(req.query.name)}!`);\n+export const page7 = (req, res) => res.send(`Welcome to page 7, ${escape(req.query.name)}!`);\n",
            "app1/package.json" => "--- a/app1/package.json\n+++ b/app1/package.json\n@@ -3,3 +3,4 @@\n   \"dependencies\": {\n-    \"express\": \"^4.19.2\"\n+    \"express\": \"^4.19.2\",\n+    \"escape-html\": \"^1.0.3\"\n   }\n",
          }
        },
        {
          files: {
            "app1/index.js" => "--- a/app1/index.js\n+++ b/app1/index.js\n@@ -1,2 +1,3 @@\n const express = require(\"express\");\n+const escape = require('escape-html');\n const {page6, page7} = require('./routes')\n@@ -4,7 +5,7 @@\n const app = express();\n-app.get(\"/\", (req, res) => res.send(`Hello, ${req.query.name}!`));\n+app.get(\"/\", (req, res) => res.send(`Hello, ${escape(req.query.name)}!`));\n \n-app.get(\"/page2\", (req, res) => res.send(`Welcome to page 2, ${req.query.name}!`));\n+app.get(\"/page2\", (req, res) => res.send(`Welcome to page 2, ${escape(req.query.name)}!`));\n \n-app.get(\"/page4\", (req, res) => res.send(`Welcome to page 4, ${req.query.name}!`));\n+app.get(\"/page4\", (req, res) => res.send(`Welcome to page 4, ${escape(req.query.name)}!`));\n \n",
            "app1/package.json" => "--- a/app1/package.json\n+++ b/app1/package.json\n@@ -3,3 +3,4 @@\n   \"dependencies\": {\n-    \"express\": \"^4.19.2\"\n+    \"express\": \"^4.19.2\",\n+    \"escape-html\": \"^1.0.3\"\n   }\n",
          }
        },
        {
          files: {
            "app2/index.js" => "--- a/app2/index.js\n+++ b/app2/index.js\n@@ -1,8 +1,9 @@\n const express = require(\"express\");\n+const escape = require('escape-html');\n \n const app = express();\n-app.get(\"/\", (req, res) => res.send(`Hello, ${req.query.name}!`));\n+app.get(\"/\", (req, res) => res.send(`Hello, ${escape(req.query.name)}!`));\n \n-app.get(\"/page2\", (req, res) => res.send(`Welcome to page 2, ${req.query.name}!`));\n+app.get(\"/page2\", (req, res) => res.send(`Welcome to page 2, ${escape(req.query.name)}!`));\n \n-app.get(\"/page4\", (req, res) => res.send(`Welcome to page 4, ${req.query.name}!`));\n+app.get(\"/page4\", (req, res) => res.send(`Welcome to page 4, ${escape(req.query.name)}!`));\n",
            "app2/package.json" => "--- a/app2/package.json\n+++ b/app2/package.json\n@@ -5,3 +5,4 @@\n     \"express\": \"^4.19.2\",\n-    \"rimraf\": \"^5.0.7\"\n+    \"rimraf\": \"^5.0.7\",\n+    \"escape-html\": \"^1.0.3\"\n   }\n",
          }
        },
        {
          files: {
            "app1/routes.js" => "--- a/app1/routes.js\n+++ b/app1/routes.js\n@@ -1,2 +1,4 @@\n-export const page6 = (req, res) => res.send(`Welcome to page 6, ${req.query.name}!`);\n-export const page7 = (req, res) => res.send(`Welcome to page 7, ${req.query.name}!`);\n+import escape from 'escape-html';\n+\n+export const page6 = (req, res) => res.send(`Welcome to page 6, ${escape(req.query.name)}!`);\n+export const page7 = (req, res) => res.send(`Welcome to page 7, ${escape(req.query.name)}!`);\n",
            "app1/package.json" => "--- a/app1/package.json\n+++ b/app1/package.json\n@@ -3,3 +3,4 @@\n   \"dependencies\": {\n-    \"express\": \"^4.19.2\"\n+    \"express\": \"^4.19.2\",\n+    \"escape-html\": \"^1.0.3\"\n   }\n",
          }
        },
      ]
      @same_content_proposed_commits = create_proposed_commits(@same_content_fixes)

      @non_overlapping_fixes = [
        {
          files: {
            "app2/index.js" => "--- a/app2/index.js\n+++ b/app2/index.js\n@@ -7 +7 @@\n-app.get(\"/page2\", (req, res) => res.send(`Welcome to page 2, ${req.query.name}!`));\n+app.get(\"/page2\", (req, res) => res.send(`Welcome to page 2, ${escape(req.query.name)}!`));\n",
          }
        },
        {
          files: {
            "app2/index.js" => "--- a/app2/index.js\n+++ b/app2/index.js\n@@ -13 +13 @@\n-app.get(\"/page8\", (req, res) => res.send(`Welcome to page 8, ${req.query.name}!`));\n+app.get(\"/page8\", (req, res) => res.send(`Welcome to page 8, ${escape(req.query.name)}!`));\n",
          }
        }
      ]
      @non_overlapping_proposed_commits = create_proposed_commits(@non_overlapping_fixes)

      @overlapping_fixes = [
        {
          files: {
            "app2/index.js" => "--- a/app2/index.js\n+++ b/app2/index.js\n@@ -7 +7 @@\n-app.get(\"/page2\", (req, res) => res.send(`Welcome to page 2, ${req.query.name}!`));\n+app.get(\"/page2\", (req, res) => res.send(`Welcome to page 2, ${escape(req.query.name)}!`));\n",
          }
        },
        {
          # Overlaps with the first fix
          files: {
            "app2/index.js" => "--- a/app2/index.js\n+++ b/app2/index.js\n@@ -5 +5 @@ const app = express();\n-app.get(\"/\", (req, res) => res.send(`Hello, ${req.query.name}!`));\n+app.get(\"/\", (req, res) => res.send(`Hello, ${escape(req.query.name)}!`));\n@@ -9 +9 @@ app.get(\"/page2\", (req, res) => res.send(`Welcome to page 2, ${req.query.name}!`\n-app.get(\"/page4\", (req, res) => res.send(`Welcome to page 4, ${req.query.name}!`));\n+app.get(\"/page4\", (req, res) => res.send(`Welcome to page 4, ${escape(req.query.name)}!`));\n",
          }
        },
        {
          # Non-overlapping
          files: {
            "app2/index.js" => "--- a/app2/index.js\n+++ b/app2/index.js\n@@ -13 +13 @@\n-app.get(\"/page8\", (req, res) => res.send(`Welcome to page 8, ${req.query.name}!`));\n+app.get(\"/page8\", (req, res) => res.send(`Welcome to page 8, ${escape(req.query.name)}!`));\n",
          }
        }
      ]
      @overlapping_proposed_commits = create_proposed_commits(@overlapping_fixes)
    end

    context "#filter_proposed_commits" do
      test "does not filter the proposed commits when all patches are different" do
        proposed_commits, removed_commits = @helper.filter_proposed_commits(@different_proposed_commits, repository: @repository)

        assert_equal 2, proposed_commits.size
        assert_equal ["Fix 0", "Fix 1"], proposed_commits.map(&:commit_message)
        assert_equal 0, removed_commits.size
      end

      test "filters the proposed commits when there are patches with the same content" do
        proposed_commits, removed_commits = @helper.filter_proposed_commits(@same_content_proposed_commits, repository: @repository)

        assert_equal 2, proposed_commits.size
        assert_equal ["Fix 0", "Fix 1"], proposed_commits.map(&:commit_message)
        assert_equal 4, removed_commits.size
      end

      test "filters the proposed commits when there is non-overlapping content" do
        GitHub.logger.expects(:info).with(
          "Filtering out proposed commit due to conflicting patches.",
          "code.namespace": "FakeHelper",
          "code.function": :filter_proposed_commits,
          "gh.repo.id": @repository.id,
          "gh.code_scanning.alert.number": 2,
          "gh.security_campaigns.file_paths": ["app2/index.js"],
        )

        proposed_commits, removed_commits = @helper.filter_proposed_commits(@non_overlapping_proposed_commits, repository: @repository)

        assert_equal 1, proposed_commits.size
        assert_equal "Fix 0", proposed_commits.first.commit_message
        assert_equal 1, removed_commits.size
      end

      test "filters the proposed commits when there is overlapping content" do
        proposed_commits, removed_commits = @helper.filter_proposed_commits(@overlapping_proposed_commits, repository: @repository)

        assert_equal 1, proposed_commits.size
        assert_equal "Fix 0", proposed_commits.first.commit_message
        assert_equal 2, removed_commits.size
      end
    end

    context "#commit_fixes" do
      test "applies the proposed commits as commits" do
        name = "test-branch-#{SecureRandom.uuid}"
        new_branch = @repository.heads.create(name, @repository.default_branch_ref.commit.oid, @user)

        messages = @helper.commit_fixes(proposed_commits: @different_proposed_commits, repository: @repository, ref: new_branch, author: @user, author_email: nil, reflog_data: nil)

        assert_equal [], messages

        new_commits = @repository.commits.history(new_branch.target_oid, 3)
        assert_equal 3, new_commits.size
        assert_equal @repository.default_branch_ref.commit.oid, new_commits.last.oid

        assert_equal "const express = require(\"express\");\n" + "const escape = require('escape-html');\n" + "const {page6, page7} = require('./routes')\n" + "\n" + "const app = express();\n" + "app.get(\"/\", (req, res) => res.send(`Hello, ${escape(req.query.name)}!`));\n" + "\n" + "app.get(\"/page2\", (req, res) => res.send(`Welcome to page 2, ${escape(req.query.name)}!`));\n" + "\n" + "app.get(\"/page4\", (req, res) => res.send(`Welcome to page 4, ${escape(req.query.name)}!`));\n" + "\n" + "app.get(\"/page6\", page6);\n" + "app.get(\"/page7\", page7);\n", @repository.blob(new_branch.target_oid, "app1/index.js").data
        assert_equal "{\n" + "  \"name\": \"@dsp-testing/koesie10-api-app1\",\n" + "  \"dependencies\": {\n" + "    \"express\": \"^4.19.2\",\n" + "    \"escape-html\": \"^1.0.3\"\n" + "  }\n" + "}\n", @repository.blob(new_branch.target_oid, "app1/package.json").data
      end
    end

    def create_proposed_commits(fixes)
      fixes.each_with_index.map do |fix, index|
        diff_entries = fix[:files].each_with_object([]) do |(path, file), out|
          file = "diff --git a/#{path} b/#{path}\n" + file
          parser = GitHub::Diff::Parser.new(file)
          parser.each do |entry|
            out << entry
          end
        end

        commit_message = "Fix #{index}"

        AutofixApplyHelper::ProposedCommit.new(commit_message:, diff_entries:, alert_number: index + 1)
      end
    end
  end
end
