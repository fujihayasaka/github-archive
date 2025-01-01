# typed: true
# frozen_string_literal: true

require "test_helper"

class ActionsWorkflowTemplatesTest < GitHub::TestCase
  fixtures do
    @owner = create :user, login: "monalisa"
    @repo = create :repository, owner: @owner, from_example: :repository_test_simple
    @repo.heads.create("main", @repo.default_branch_ref.commit.oid, @repo.owner)
    @repo.update_default_branch("main")
    @repo.heads.create("protected", @repo.default_branch_ref.commit.oid, @repo.owner)
    @repo.protect_branch("foo_protected_bar", creator: @repo.owner, entry_point: :test_case)
    # Note that branch protection rules use fnmatch syntax - these aren't regexes
    @repo.protect_branch("wildcard_name?", creator: @repo.owner, entry_point: :test_case)
    @repo.protect_branch("[a-z][A-Z]", creator: @repo.owner, entry_point: :test_case)

    @templates = [
      {
        "id" => "blank",
        "data" => Base64.encode64(<<~YAML
on:
  push:
    branches:
      - $default-branch
  jobs:
    build:
      runs-on: ${{ (matrix.language == 'swift' && 'macos-latest') || 'ubuntu-latest' }}
      steps:
        - uses: actions/checkout@main
          env:
            REGISTRY: $registry-url(npm)
      YAML
        ),
        "name" => "Simple workflow",
        "categories" => ["Test"]
      },
      {
        "id" => "simple",
        "data" => Base64.encode64(<<~YAML
on:
  push:
    branches:
      - $default-branch
  jobs:
    build:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@main
          env:
            REGISTRY: $registry-url(npm)
      YAML
        ),
        "name" => "Simple workflow with simpler runs-on line",
        "categories" => ["Test"]
      },
      {
        "id" => "code-scanning-example",
        "data" => Base64.encode64(<<~YAML
name: "CodeQL"
# NB invalid for actions, but still valid for testing! :-)
on:
  push:
    - branches: [ $default-branch, $protected-branches ]

  pull_request:
    # The branches below must be a subset of the branches above
    - branches: [ $default-branch, ]
    - branches: [ $protected-branches ]
  schedule:
    - cron: $cron-hourly
    - cron: $cron-daily
    - cron: $cron-weekly

jobs:
  analyze:
    name: Analyze
    runs-on: windows-latest

    strategy:
      fail-fast: false
      matrix:
        language: [ $detected-codeql-languages ]
        # CodeQL supports [ $supported-codeql-languages ]
      YAML
        ),
        "name" => "Code Scanning workflow",
        "categories" => ["Code Scanning Test"]
      },
      {
        "id" => "automation",
        "data" => "<some-data>",
        "categories" => ["Automation"]
      },
      {
        "id" => "code-scanning-matrix-example",
        "data" => Base64.encode64(<<~YAML
name: "CodeQL"
# NB invalid for actions, but still valid for testing! :-)
jobs:
  analyze:
    name: Analyze
    runs-on: windows-latest
    strategy:
      matrix:
        $codeql-languages-matrix
      YAML
        ),
        "name" => "Code Scanning workflow",
        "categories" => ["Code Scanning Test"]
      },
      {
        "id" => "automation",
        "data" => "<some-data>",
        "categories" => ["Automation"]
      }
    ]

    @enterpriseTemplates = @templates + [{
      "id" => "enterprise",
      "data" => "<some-data>",
      "categories" => ["Enterprise"],
    }]
  end

  setup do
    templates = GitHub.enterprise? ? @enterpriseTemplates : @templates
    Actions::WorkflowTemplatesLoader.any_instance.stubs(:all).returns(templates)
    @repo.language_analysis.stubs(:language_percentages).returns([["foobar", 123], ["javascript", 456], ["go", 789]])
  end

  def build_template
    Actions::WorkflowTemplates.new(@repo, @owner)
  end

  context "#all" do
    if GitHub.enterprise?
      test "loads from the repository" do
        res = build_template.get_by_category "Test"
        assert res.any? { |t| t["id"] == "blank" }
      end

      test "loads from the organization .github repository if it exists" do
        orgRepo = create :repository, owner: @owner, name: ".github"

        orgLoader = mock("loader")
        orgLoader.stubs(:all).returns([{
          "id" => "org-template",
          "data" => "<some-data>",
          "categories" => ["Org"],
        }])

        Actions::WorkflowTemplatesLoader.expects(:new)
          .with("#{@repo.owner.login}/.github", ["workflow-templates"], "owner")
          .returns(orgLoader)


        defaultLoader = mock("loader")
        defaultLoader.stubs(:all).returns(@templates)

        Actions::WorkflowTemplatesLoader.expects(:new)
          .with(GitHub.actions_starter_workflows_nwo, Actions::WorkflowTemplates::STARTER_WORKFLOWS_FOLDERS, "default", @owner)
          .returns(defaultLoader)

        res = build_template.all
        assert res.any? { |t| t["id"] == "org-template" }
        assert res.any? { |t| t["id"] == "blank" }
      end
    else
      context "loads from the default repository from git" do
        test "for users" do
          on_multi_tenant_enterprise do
            setup_workflow_repositories owner_type: :user, multi_tenant: true
            test_template_availability "default", public: true, private: true
          end
        end

        test "for organizations" do
          on_multi_tenant_enterprise do
            setup_workflow_repositories owner_type: :organization, multi_tenant: true
            test_template_availability "default", public: true, private: true
          end
        end

        test "for enterprise linked organizations" do
          on_multi_tenant_enterprise do
            setup_workflow_repositories owner_type: :enterprise_linked_organization, multi_tenant: true
            test_template_availability "default", public: true, private: true, internal: true
          end
        end
      end

      context "loads from the default repository from GraphQL" do
        test "for users" do
          setup_workflow_repositories owner_type: :user
          test_template_availability "default", public: true, private: true
        end

        test "for organizations" do
          setup_workflow_repositories owner_type: :organization
          test_template_availability "default", public: true, private: true
        end

        test "for enterprise linked organizations" do
          setup_workflow_repositories owner_type: :enterprise_linked_organization
          test_template_availability "default", public: true, private: true, internal: true
        end
      end

      context "loads from the .github repository" do
        test "in public repos only, regardless of the internal_workflow_templates feature flag" do
          setup_workflow_repositories owner_type: :user, github_template: :public

          GitHub.flipper[:internal_workflow_templates].enable
          test_template_availability "org-public", public: true, private: false

          GitHub.flipper[:internal_workflow_templates].disable
          test_template_availability "org-public", public: true, private: false
        end

        test "in all visibility repos for business_plus organizations, regardless of the internal_workflow_templates feature flag" do
          setup_workflow_repositories owner_type: :organization, github_template: :public

          GitHub.flipper[:internal_workflow_templates].enable
          test_template_availability "org-public", public: true, private: true

          GitHub.flipper[:internal_workflow_templates].disable
          test_template_availability "org-public", public: true, private: true
        end

        test "in all visibility repos for enterprises linked organizations, regardless of the internal_workflow_templates feature flag" do
          setup_workflow_repositories owner_type: :enterprise_linked_organization, github_template: :public

          GitHub.flipper[:internal_workflow_templates].enable
          test_template_availability "org-public", public: true, private: true, internal: true

          GitHub.flipper[:internal_workflow_templates].disable
          test_template_availability "org-public", public: true, private: true, internal: true
        end

        test "unless the .github repository is private" do
          setup_workflow_repositories owner_type: :user, github_template: :private
          test_template_availability "org-public", public: false, private: false
        end

        test "unless the .github repository is internal" do
          setup_workflow_repositories owner_type: :enterprise_linked_organization, github_template: :internal
          test_template_availability "org-public", public: false, private: false, internal: false
        end
      end

      context "loads from the .github-internal repository if feature flag internal_private_workflow_templates is enabled" do
        test "for enterprise linked organizations, when template stored in internal repository and accessed from internal and private repositories" do
          GitHub.flipper[:internal_private_workflow_templates].enable
          setup_workflow_repositories owner_type: :enterprise_linked_organization, github_internal_template: :internal
          test_template_availability "org-internal", public: false, private: true, internal: true
        end

        test "unless the .github-internal repository is public" do
          GitHub.flipper[:internal_private_workflow_templates].enable
          setup_workflow_repositories owner_type: :user, github_internal_template: :public
          test_template_availability "org-internal", public: false, private: false, internal: false
        end

        test "unless the .github-internal repository is private" do
          GitHub.flipper[:internal_private_workflow_templates].enable
          setup_workflow_repositories owner_type: :user, github_internal_template: :private
          test_template_availability "org-internal", public: false, private: false, internal: false
        end

        test "unless the feature flag internal_private_workflow_templates is disabled" do
          GitHub.flipper[:internal_private_workflow_templates].disable
          setup_workflow_repositories owner_type: :enterprise_linked_organization, github_internal_template: :internal
          test_template_availability "org-internal", public: false, private: false, internal: false
        end
      end

      context "loads from the .github-private repository if feature flag internal_private_workflow_templates is enabled" do
        test "unless for user" do
          GitHub.flipper[:internal_private_workflow_templates].enable
          setup_workflow_repositories owner_type: :user, github_private_template: :private
          test_template_availability "org-private", public: false, private: false, internal: false
        end

        test "for business_plus organizations and enterprise linked organizations, when template stored in private repository and accessed from private repositories" do
          GitHub.flipper[:internal_private_workflow_templates].enable
          setup_workflow_repositories owner_type: :organization, github_private_template: :private
          test_template_availability "org-private", public: false, private: true

          setup_workflow_repositories owner_type: :enterprise_linked_organization, github_private_template: :private
          test_template_availability "org-private", public: false, private: true
        end

        test "unless the .github-private repository is public" do
          GitHub.flipper[:internal_private_workflow_templates].enable
          setup_workflow_repositories owner_type: :user, github_private_template: :public
          test_template_availability "org-private", public: false, private: false, internal: false
        end

        test "unless the .github-private repository is internal" do
          GitHub.flipper[:internal_private_workflow_templates].enable
          setup_workflow_repositories owner_type: :enterprise_linked_organization, github_private_template: :internal
          test_template_availability "org-private", public: false, private: false, internal: false
        end

        test "unless the feature flag internal_private_workflow_templates is disabled" do
          GitHub.flipper[:internal_private_workflow_templates].disable
          setup_workflow_repositories owner_type: :enterprise_linked_organization, github_private_template: :private
          test_template_availability "org-private", public: false, private: false, internal: false
        end
      end

      context "loads from the .github-local repository" do
        test "unless for user" do
          GitHub.flipper[:internal_workflow_templates].enable
          setup_workflow_repositories owner_type: :user, github_template: :none, github_local_template: :private
          test_template_availability "org-local", public: false, private: false
        end

        test "for business_plus organizations, when template stored in private repository and accessed from private repositories" do
          GitHub.flipper[:internal_workflow_templates].enable
          setup_workflow_repositories owner_type: :organization, github_template: :none, github_local_template: :private
          test_template_availability "org-local", public: false, private: true
        end

        test "for enterprise linked organizations, when template stored in internal repository and accessed from internal or private repositories" do
          GitHub.flipper[:internal_workflow_templates].enable
          setup_workflow_repositories owner_type: :enterprise_linked_organization, github_template: :none, github_local_template: :internal
          test_template_availability "org-local", public: false, private: true, internal: true
        end

        test "for enterprise linked organizations, when template stored in private repository and accessed from internal or private repositories" do
          GitHub.flipper[:internal_workflow_templates].enable
          setup_workflow_repositories owner_type: :enterprise_linked_organization, github_template: :none, github_local_template: :private
          test_template_availability "org-local", public: false, private: true, internal: true
        end

        test "if the .github-local repository is public" do
          GitHub.flipper[:internal_workflow_templates].enable
          setup_workflow_repositories owner_type: :organization, github_template: :none, github_local_template: :public
          test_template_availability "org-local", public: false, private: true

          setup_workflow_repositories owner_type: :enterprise_linked_organization, github_template: :none, github_local_template: :public
          test_template_availability "org-local", public: false, private: true, internal: true
        end

        test "unless the feature flag internal_workflow_templates is disabled" do
          GitHub.flipper[:internal_workflow_templates].disable
          setup_workflow_repositories owner_type: :enterprise_linked_organization, github_template: :none, github_local_template: :internal
          test_template_availability "org-local", public: false, private: false, internal: false
        end
      end
    end

    test "returns templates with uniq ids prioritising org-level over default" do
      @owner = create :organization, plan: "business_plus"
      @repo = create(:private_repository, owner: @owner)
      create :repository, owner: @owner, name: ".github"

      default_templates = [{ "id" => "blank", "data" => "default" }]
      default_loader = mock("loader")
      default_loader.stubs(:all).returns(default_templates)
      Actions::WorkflowTemplatesLoader.expects(:new)
        .with(GitHub.actions_starter_workflows_nwo, Actions::WorkflowTemplates::STARTER_WORKFLOWS_FOLDERS, "default", @owner)
        .returns(default_loader)

      org_templates = [{ "id" => "blank", "data" => "org" }]
      org_loader = mock("loader")
      org_loader.stubs(:all).returns(org_templates)
      Actions::WorkflowTemplatesLoader.expects(:new)
        .with("#{@repo.owner.login}/.github", ["workflow-templates"], "owner")
        .returns(org_loader)

      templates = build_template.all.map { |t| t["data"] }
      assert_includes templates, "org"
      refute_includes templates, "default"
    end

    test "returns templates with uniq ids prioritising org-level in order of private, internal and public" do
      GitHub.flipper[:internal_private_workflow_templates].enable
      @owner = create :enterprise_linked_organization, plan: "business_plus"
      @repo = create(:private_repository, owner: @owner)
      create :repository, owner: @owner, name: ".github"
      create :internal_repository, owner: @owner, name: ".github-internal"
      create(:private_repository, owner: @owner, name: ".github-private")

      default_loader = mock("loader")
      default_loader.stubs(:all).returns([])
      Actions::WorkflowTemplatesLoader.stubs(:new)
        .returns(default_loader)

      org_public_templates = [{ "id" => "blank", "data" => "org-public" }]
      org_public_loader = mock("loader")
      org_public_loader.stubs(:all).returns(org_public_templates)
      Actions::WorkflowTemplatesLoader.stubs(:new)
        .with("#{@repo.owner.login}/.github", ["workflow-templates"], "owner")
        .returns(org_public_loader)

      org_internal_templates = [{ "id" => "blank", "data" => "org-internal" }]
      org_internal_loader = mock("loader")
      org_internal_loader.stubs(:all).returns(org_internal_templates)
      Actions::WorkflowTemplatesLoader.stubs(:new)
        .with("#{@repo.owner.login}/.github-internal", ["workflow-templates"], "owner")
        .returns(org_internal_loader)

      # When only internal and public owner templates are available, the internal templates are returned
      templates = build_template.all.map { |t| t["data"] }
      assert_includes templates, "org-internal"
      refute_includes templates, "org-public"

      org_private_templates = [{ "id" => "blank", "data" => "org-private" }]
      org_private_loader = mock("loader")
      org_private_loader.stubs(:all).returns(org_private_templates)
      Actions::WorkflowTemplatesLoader.stubs(:new)
        .with("#{@repo.owner.login}/.github-private", ["workflow-templates"], "owner")
        .returns(org_private_loader)

      # When private, internal and public owner templates are available, the private templates are returned
      templates = build_template.all.map { |t| t["data"] }
      assert_includes templates, "org-private"
      refute_includes templates, "org-internal"
      refute_includes templates, "org-public"
    end
  end

  context "#get_by_id" do
    test "gets a workflow" do
      res = build_template.get_by_id "blank"
      assert_equal "Simple workflow", res["name"]
    end

    unless GitHub.enterprise?
      test "prioritises org-level public templates over default repository" do
        @owner = create :organization, plan: "business_plus"
        @repo = create(:private_repository, owner: @owner)
        create :repository, owner: @owner, name: ".github"

        default_templates = [{ "id" => "blank", "data" => "default" }]
        default_loader = mock("loader")
        default_loader.stubs(:all).returns(default_templates)
        Actions::WorkflowTemplatesLoader.expects(:new)
          .with(GitHub.actions_starter_workflows_nwo, Actions::WorkflowTemplates::STARTER_WORKFLOWS_FOLDERS, "default", @owner)
          .returns(default_loader)

        org_templates = [{ "id" => "blank", "data" => "org" }]
        org_loader = mock("loader")
        org_loader.stubs(:all).returns(org_templates)
        Actions::WorkflowTemplatesLoader.expects(:new)
          .with("#{@repo.owner.login}/.github", ["workflow-templates"], "owner")
          .returns(org_loader)

        res = build_template.get_by_id "blank"
        assert_equal "org", res["data"]
      end

      test "prioritizes org-level in-order of local, private, internal and then public templates in a private repository" do
        GitHub.flipper[:internal_private_workflow_templates].enable
        GitHub.flipper[:internal_workflow_templates].enable
        @owner = create :enterprise_linked_organization
        @repo = create(:private_repository, owner: @owner)
        create :repository, owner: @owner, name: ".github"
        create :internal_repository, owner: @owner, name: ".github-internal"
        create(:private_repository, owner: @owner, name: ".github-private")
        create :internal_repository, owner: @owner, name: ".github-local"

        # When default, org-level private, public or internal templates are unavailable, empty list is returned
        default_loader = mock("loader")
        default_loader.stubs(:all).returns([])
        Actions::WorkflowTemplatesLoader.stubs(:new)
          .returns(default_loader)

        org_public_templates = [{ "id" => "blank", "data" => "org-public" }]
        org_public_loader = mock("loader")
        org_public_loader.stubs(:all).returns(org_public_templates)
        Actions::WorkflowTemplatesLoader.stubs(:new)
          .with("#{@repo.owner.login}/.github", ["workflow-templates"], "owner")
          .returns(org_public_loader)

        # When only public owner templates are available, the public templates are returned
        res = build_template.get_by_id "blank"
        assert_equal "org-public", res["data"]

        org_internal_templates = [{ "id" => "blank", "data" => "org-internal" }]
        org_internal_loader = mock("loader")
        org_internal_loader.stubs(:all).returns(org_internal_templates)
        Actions::WorkflowTemplatesLoader.stubs(:new)
          .with("#{@repo.owner.login}/.github-internal", ["workflow-templates"], "owner")
          .returns(org_internal_loader)

        # When only internal and public owner templates are available, the internal templates are returned
        res = build_template.get_by_id "blank"
        assert_equal "org-internal", res["data"]

        org_private_templates = [{ "id" => "blank", "data" => "org-private" }]
        org_private_loader = mock("loader")
        org_private_loader.stubs(:all).returns(org_private_templates)
        Actions::WorkflowTemplatesLoader.stubs(:new)
          .with("#{@repo.owner.login}/.github-private", ["workflow-templates"], "owner")
          .returns(org_private_loader)

        # When only private, internal and public owner templates are available, the private templates are returned
        res = build_template.get_by_id "blank"
        assert_equal "org-private", res["data"]

        org_local_templates = [{ "id" => "blank", "data" => "org-local" }]
        org_local_loader = mock("loader")
        org_local_loader.stubs(:all).returns(org_local_templates)
        Actions::WorkflowTemplatesLoader.stubs(:new)
          .with("#{@repo.owner.login}/.github-local", ["workflow-templates"], "owner")
          .returns(org_local_loader)

        # When local, private, internal and public owner templates are available, the local templates are returned
        res = build_template.get_by_id "blank"
        assert_equal "org-local", res["data"]
      end

      test "doesn't access org-level internal templates from public repositories" do
        GitHub.flipper[:internal_private_workflow_templates].enable
        @owner = create :enterprise_linked_organization
        @repo = create(:public_repository, owner: @owner)
        create :internal_repository, owner: @owner, name: ".github-internal"

        default_templates = [{ "id" => "something-else", "data" => "default" }]
        default_loader = mock("loader")
        default_loader.stubs(:all).returns(default_templates)
        Actions::WorkflowTemplatesLoader.stubs(:new)
          .with(GitHub.actions_starter_workflows_nwo, Actions::WorkflowTemplates::STARTER_WORKFLOWS_FOLDERS, "default", @owner)
          .returns(default_loader)

        org_internal_templates = [{ "id" => "blank", "data" => "org-internal" }]
        org_internal_loader = mock("loader")
        org_internal_loader.stubs(:all).returns(org_internal_templates)
        Actions::WorkflowTemplatesLoader.stubs(:new)
          .with("#{@repo.owner.login}/.github-internal", ["workflow-templates"], "owner")
          .returns(org_internal_loader)

        res = build_template.get_by_id "blank"
        assert_nil res
      end

      test "doesn't access org-level private templates from public or internal repositories" do
        GitHub.flipper[:internal_private_workflow_templates].enable
        @owner = create :enterprise_linked_organization
        @repo = create(:public_repository, owner: @owner)
        create(:private_repository, owner: @owner, name: ".github-private")

        # When default, org-level private, public or internal templates are unavailable, empty list is returned
        empty_loader = mock("loader")
        empty_loader.stubs(:all).returns([])
        Actions::WorkflowTemplatesLoader.stubs(:new)
          .returns(empty_loader)

        default_templates = [{ "id" => "something-else", "data" => "default" }]
        default_loader = mock("loader")
        default_loader.stubs(:all).returns(default_templates)
        Actions::WorkflowTemplatesLoader.stubs(:new)
          .with(GitHub.actions_starter_workflows_nwo, Actions::WorkflowTemplates::STARTER_WORKFLOWS_FOLDERS, "default", @owner)
          .returns(default_loader)

        org_private_templates = [{ "id" => "blank", "data" => "org-private" }]
        org_private_loader = mock("loader")
        org_private_loader.stubs(:all).returns(org_private_templates)
        Actions::WorkflowTemplatesLoader.stubs(:new)
          .with("#{@repo.owner.login}/.github-private", ["workflow-templates"], "owner")
          .returns(org_private_loader)

        # When repo is internal, org-level private templates are not returned
        res = build_template.get_by_id "blank"
        assert_nil res

        @repo = create :internal_repository, owner: @owner

        # When repo is internal, org-level private templates are not returned
        res = build_template.get_by_id "blank"
        assert_nil res
      end

      test "doesn't access local templates from public repositories" do
        GitHub.flipper[:internal_workflow_templates].enable
        @owner = create :enterprise_linked_organization
        @repo = create(:public_repository, owner: @owner)
        create :internal_repository, owner: @owner, name: ".github-local"

        default_templates = [{ "id" => "something-else", "data" => "default" }]
        default_loader = mock("loader")
        default_loader.stubs(:all).returns(default_templates)
        Actions::WorkflowTemplatesLoader.expects(:new)
          .with(GitHub.actions_starter_workflows_nwo, Actions::WorkflowTemplates::STARTER_WORKFLOWS_FOLDERS, "default", @owner)
          .returns(default_loader)

        org_local_templates = [{ "id" => "blank", "data" => "org-local" }]
        org_local_loader = mock("loader")
        org_local_loader.stubs(:all).returns(org_local_templates)
        Actions::WorkflowTemplatesLoader.stubs(:new)
          .with("#{@repo.owner.login}/.github-local", ["workflow-templates"], "owner")
          .returns(org_local_loader)

        res = build_template.get_by_id "blank"
        assert_nil res
      end
    end
  end

  context "#get_by_category" do
    test "loads from the repository" do
      res = build_template.get_by_category "Test"
      assert res.any? { |t| t["id"] == "blank" }
    end
  end

  context "#get_yaml_by_id" do
    if GitHub.enterprise?
      test "Replaces ubuntu-latest with runner labels array and similar for MacOS" do
        res = Actions::WorkflowTemplates.get_yaml_by_id "blank", @repo, @owner
        # Ensure that the template no longer contains a line like
        # runs-on: ${{ (matrix.language == 'swift' && 'macos-latest') || 'ubuntu-latest' }}
        refute_match "macos-latest", res
        refute_match "ubuntu-latest", res

        assert_match "runs-on: ${{ (matrix.language == 'swift' && fromJSON('[ \"self-hosted\", \"macOS\" ]')) || 'self-hosted' }}", res
      end
      test "Can correctly replace ubuntu-latest regardless of quotes" do
        res = Actions::WorkflowTemplates.get_yaml_by_id "simple", @repo, @owner
        refute_match "ubuntu-latest", res # we don't want anything like `runs-on: ubuntu-latest`
        assert_match "runs-on: [ self-hosted ]", res
      end
      test "Replaces windows-latest with runner labels array" do
        res = Actions::WorkflowTemplates.get_yaml_by_id "code-scanning-example", @repo, @owner
        refute_match "windows-latest", res # we don't want anything like `runs-on: windows-latest`
        assert_match "runs-on: [ self-hosted, windows ]", res
      end
    else
      test "Does not replace with runner labels array" do
        res = Actions::WorkflowTemplates.get_yaml_by_id "blank", @repo, @owner
        assert_match "runs-on: ${{ (matrix.language == 'swift' && 'macos-latest') || 'ubuntu-latest' }}", res
        refute_match "self-hosted", res # we don't want anything like `runs-on: [ self-hosted ]`

        res = Actions::WorkflowTemplates.get_yaml_by_id "simple", @repo, @owner
        assert_match "runs-on: ubuntu-latest", res
        refute_match "self-hosted", res # we don't want anything like `runs-on: [ self-hosted ]`
      end
      test "Does not replace windows-latest with runner labels array" do
        res = Actions::WorkflowTemplates.get_yaml_by_id "code-scanning-example", @repo, @owner
        assert_match "runs-on: windows-latest", res

        # We don't want anything like runs-on: [ self-hosted, windows ]
        refute_match "self-hosted", res
        refute_match /["']windows["']/, res # have to include some quotes since `windows-latest` is okay
      end
    end

    test "Replaces ubuntu-latest with runner labels array (and similar for MacOS) for Codespaces development" do
      begin
        Rails.env.stubs(:development?).returns(true)
        ENV["CODESPACES"] = "true"

        res = Actions::WorkflowTemplates.get_yaml_by_id "blank", @repo, @owner
        # We don't want anything like this:
        # runs-on: ${{ (matrix.language == 'swift' && 'macos-latest') || 'ubuntu-latest' }}
        refute_match "macos-latest", res
        refute_match "ubuntu-latest", res

        assert_match "runs-on: ${{ (matrix.language == 'swift' && fromJSON('[ \"self-hosted\", \"macOS\" ]')) || 'self-hosted' }}", res

        # Can manage the replacement regardless of quotes
        res = Actions::WorkflowTemplates.get_yaml_by_id "simple", @repo, @owner
        refute_match "ubuntu-latest", res # we don't want anything like `runs-on: ubuntu-latest`
        assert_match "runs-on: [ self-hosted ]", res
      ensure
        ENV.delete("CODESPACES")
      end
    end

    test "Replaces windows-latest with runner labels array for Codespaces development"  do
      begin
        Rails.env.stubs(:development?).returns(true)
        ENV["CODESPACES"] = "true"

        res = Actions::WorkflowTemplates.get_yaml_by_id "code-scanning-example", @repo, @owner
        refute_match "runs-on: windows-latest", res
        assert_match "runs-on: [ self-hosted, windows ]", res
      ensure
        ENV.delete("CODESPACES")
      end
    end

    test "replaces default-branch token, quoting the branch name" do
      res = Actions::WorkflowTemplates.get_yaml_by_id "blank", @repo, @owner
      assert_match /- "main"/, res
      refute_match /\$default-branch/, res
    end

    test "replaces protected-branches token, handling fnmatch glob syntax" do
      res = Actions::WorkflowTemplates.get_yaml_by_id "code-scanning-example", @repo, @owner
      assert_match "\"foo_protected_bar\"", res # normal names are quoted but otherwise unchanged
      assert_match "\"[a-z][A-Z]\"", res # same for fnmatch values without '?'
      assert_match "\"wildcard_name[a-zA-Z0-9]\"", res # the fnmatch '?' is replaced by a range
      refute_match "$protected-branches", res
    end

    test "protected branches list doesn't include default branch" do
      @repo.protect_branch("main", creator: @repo.owner, entry_point: :test_case)

      # The template above includes these two lines:
      # - branches: [ $default-branch, $protected-branches ]
      # - branches: [ $protected-branches ]
      # Here we assert that the first line doesn't include the default branch twice
      # and that that second doesn't include it at all.
      res = Actions::WorkflowTemplates.get_yaml_by_id "code-scanning-example", @repo, @owner
      assert_match "- branches: [ \"main\", \"[a-z][A-Z]\", \"foo_protected_bar\", \"wildcard_name[a-zA-Z0-9]\" ]", res
      assert_match "- branches: [ \"[a-z][A-Z]\", \"foo_protected_bar\", \"wildcard_name[a-zA-Z0-9]\" ]", res
    end

    test "cleans up trailing commas in arrays" do
      res = Actions::WorkflowTemplates.get_yaml_by_id "code-scanning-example", @repo, @owner
      refute_match /\,\s*\]/, res
      assert_match /\[.*,.*\]/, res
    end

    test "replaces $cron-* tokens" do
      # fixing the seed seemed to work different locally versus in CI
      SecureRandom.stubs(:rand).with(15..45).returns(20)
      SecureRandom.stubs(:rand).with(0..23).returns(2)
      SecureRandom.stubs(:rand).with(0..6).returns(6)

      res = Actions::WorkflowTemplates.get_yaml_by_id "code-scanning-example", @repo, @owner
      refute_match /\$cron-hourly/, res
      refute_match /\$cron-daily/, res
      refute_match /\$cron-weekly/, res

      assert_match /\'20 \* \* \* \*\'/, res
      assert_match /\'20 2 \* \* \*\'/, res
      assert_match /\'20 2 \* \* 6\'/, res
    end

    test "replaces detected-codeql-languages token" do
      res = Actions::WorkflowTemplates.get_yaml_by_id "code-scanning-example", @repo, @owner
      refute_match /\$detected-codeql-languages/, res
      assert_match /language\: \[ 'go', 'javascript-typescript' \]/, res
    end

    test "replaces supported-codeql-languages token" do
      res = Actions::WorkflowTemplates.get_yaml_by_id "code-scanning-example", @repo, @owner
      refute_match /\$supported-codeql-languages/, res
      assert res.include?(@repo.supported_codeql_languages_string)
    end

    test "replaces codeql-languages-matrix token" do
      res = Actions::WorkflowTemplates.get_yaml_by_id "code-scanning-matrix-example", @repo, @owner
      refute_match /\$codeql-languages-matrix-languages/, res
      matrix_block = <<-EOS
\n        include:
        - language: go
          build-mode: autobuild
        - language: javascript-typescript
          build-mode: none
EOS
      assert res.include?(matrix_block)
    end

    test "returns utf-8 text" do
      res = Actions::WorkflowTemplates.get_yaml_by_id "blank", @repo, @owner
      assert_equal Encoding::UTF_8, res.encoding
    end

    test "replaces the $registry-url(npm) token" do
      res = Actions::WorkflowTemplates.get_yaml_by_id "blank", @repo, @owner
      assert_match /REGISTRY: #{GitHub.urls.registry_url(:npm)}/, res
      refute_match /\$registry-url\(npm\)/, res
    end
  end

  private

  def setup_workflow_repositories(owner_type:, github_template: :none, github_local_template: :none, github_internal_template: :none, github_private_template: :none, multi_tenant: false)
    case owner_type
    when :user
      # Handled by fixture
    when :organization
      @owner = create :organization, plan: "business_plus"
    when :enterprise_linked_organization
      @owner = create :enterprise_linked_organization
    end

    default_templates = [{ "id" => "default", "data" => "default" }]
    default_loader = mock("loader")
    default_loader.stubs(:all).returns(default_templates)

    if multi_tenant
      Actions::Proxima::WorkflowTemplatesLoader.stubs(:new)
        .with(GitHub.actions_starter_workflows_nwo, Actions::WorkflowTemplates::STARTER_WORKFLOWS_FOLDERS, "default", "main")
        .returns(default_loader)
    else
      Actions::WorkflowTemplatesLoader.stubs(:new)
        .with(GitHub.actions_starter_workflows_nwo, Actions::WorkflowTemplates::STARTER_WORKFLOWS_FOLDERS, "default", @owner)
        .returns(default_loader)
    end

    case github_template
    when :public
      create :repository, owner: @owner, name: ".github"
      setup_org_public_template_loader
    when :internal
      if owner_type != :enterprise_linked_organization then raise "Only orgs under enterprises can have internal repos" end
      create :internal_repository, owner: @owner, name: ".github"
      setup_org_public_template_loader
    when :private
      create(:private_repository, owner: @owner, name: ".github")
      setup_org_public_template_loader
    end

    case github_internal_template
    when :public
      create(:public_repository, owner: @owner, name: ".github-internal")
      setup_org_internal_template_loader
    when :internal
      if owner_type != :enterprise_linked_organization then raise "Only orgs under enterprises can have internal repos" end
      create :internal_repository, owner: @owner, name: ".github-internal"
      setup_org_internal_template_loader
    when :private
      create(:private_repository, owner: @owner, name: ".github-internal")
      setup_org_internal_template_loader
    end

    case github_private_template
    when :public
      create :repository, owner: @owner, name: ".github-private"
      setup_org_private_template_loader
    when :internal
      if owner_type != :enterprise_linked_organization then raise "Only orgs under enterprises can have internal repos" end
      create :internal_repository, owner: @owner, name: ".github-private"
      setup_org_private_template_loader
    when :private
      create(:private_repository, owner: @owner, name: ".github-private")
      setup_org_private_template_loader
    end

    case github_local_template
    when :public
      create :repository, owner: @owner, name: ".github-local"
      setup_org_local_template_loader
    when :internal
      if owner_type != :enterprise_linked_organization then raise "Only orgs under enterprises can have internal repos" end
      create :internal_repository, owner: @owner, name: ".github-local"
      setup_org_local_template_loader
    when :private
      create(:private_repository, owner: @owner, name: ".github-local")
      setup_org_local_template_loader
    end

    setup_test_repositories
  end

  def setup_org_public_template_loader
    org_public_templates = [{ "id" => "org-public", "data" => "public template data" }]
    org_public_loader = mock("loader")
    org_public_loader.stubs(:all).returns(org_public_templates)
    Actions::WorkflowTemplatesLoader.stubs(:new)
      .with("#{@owner.login}/.github", ["workflow-templates"], "owner")
      .returns(org_public_loader)
  end

  def setup_org_internal_template_loader
    org_internal_templates = [{ "id" => "org-internal", "data" => "internal template data" }]
    org_internal_loader = mock("loader")
    org_internal_loader.stubs(:all).returns(org_internal_templates)
    Actions::WorkflowTemplatesLoader.stubs(:new)
      .with("#{@owner.login}/.github-internal", ["workflow-templates"], "owner")
      .returns(org_internal_loader)
  end

  def setup_org_private_template_loader
    org_private_templates = [{ "id" => "org-private", "data" => "private template data" }]
    org_private_loader = mock("loader")
    org_private_loader.stubs(:all).returns(org_private_templates)
    Actions::WorkflowTemplatesLoader.stubs(:new)
      .with("#{@owner.login}/.github-private", ["workflow-templates"], "owner")
      .returns(org_private_loader)
  end

  def setup_org_local_template_loader
    org_local_templates = [{ "id" => "org-local", "data" => "local template data" }]
    org_local_loader = mock("loader")
    org_local_loader.stubs(:all).returns(org_local_templates)
    Actions::WorkflowTemplatesLoader.stubs(:new)
      .with("#{@owner.login}/.github-local", ["workflow-templates"], "owner")
      .returns(org_local_loader)
  end

  def setup_test_repositories
    @public_repo = create(:public_repository, owner: @owner)
    @templates_available_to_public_repo = Actions::WorkflowTemplates.new(@public_repo, @owner)
    @private_repo = create(:private_repository, owner: @owner)
    @templates_available_to_private_repo = Actions::WorkflowTemplates.new(@private_repo, @owner)
    if @owner.organization? && @owner.business
      @internal_repo = create :internal_repository, owner: @owner
      @templates_available_to_internal_repo = Actions::WorkflowTemplates.new(@internal_repo, @owner)
    end
  end

  def test_template_availability(id, public: false, private: false, internal: false)
    res = @templates_available_to_public_repo.all
    assert res.any? { |t| t["id"] == id } == public, "#{id} should #{"not " unless public}be visible to the public repo"
    res = @templates_available_to_private_repo.all
    assert res.any? { |t| t["id"] == id } == private, "#{id} should #{"not " unless private}be visible to the private repo"
    if @owner.organization? && @owner.business
      res = @templates_available_to_internal_repo.all
      assert res.any? { |t| t["id"] == id } == internal, "#{id} should #{"not " unless internal}be visible to the internal repo"
    end
  end
end
