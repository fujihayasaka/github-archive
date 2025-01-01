# typed: true
# frozen_string_literal: true

require "test_helper"

class Actions::WorkflowPatternTest < GitHub::TestCase
  fixtures do
    @enterprise = create(:business)
    @org = create(:organization, business: @enterprise, name: "octo-org")
    @org_repo = create(:repository, owner: @org, name: "octo-repo")
  end

  context "validations" do
    test "validates that a plausibly-well-formed raw string was provided" do
      instance = Actions::WorkflowPattern.new(
        "wat",
        owner: @org
      )

      assert_predicate instance, :invalid?
      assert_includes instance.errors[:base], 'Workflow "wat" is malformed. Format should be: owner/repo/path/to/workflow.yaml@ref'
    end

    test "validates that a ref was provided" do
      instance = Actions::WorkflowPattern.new(
        "octo-org/octo-repo/.github/workflows/foo.yaml",
        owner: @org
      )

      assert_predicate instance, :invalid?
      assert_includes instance.errors[:base], 'Workflow "octo-org/octo-repo/.github/workflows/foo.yaml" must be pinned to a ref, tag, or full SHA.'
    end

    test "validates that a ref was provided (works even with trailing `@')" do
      instance = Actions::WorkflowPattern.new(
        "octo-org/octo-repo/.github/workflows/foo.yaml@",
        owner: @org
      )

      assert_predicate instance, :invalid?
      assert_includes instance.errors[:base], 'Workflow "octo-org/octo-repo/.github/workflows/foo.yaml@" must be pinned to a ref, tag, or full SHA.'
    end

    test "validates that a ref was provided (works even with `@' in path name)" do
      instance = Actions::WorkflowPattern.new(
        "octo-org/octo@home/.github/w@rkflows/foo.yaml@",
        owner: @org
      )

      assert_predicate instance, :invalid?
      assert_includes instance.errors[:base], 'Workflow "octo-org/octo@home/.github/w@rkflows/foo.yaml@" must be pinned to a ref, tag, or full SHA.'
    end

    test "validates that the workflow path is begins with `:owner/:repo`" do
      instance = Actions::WorkflowPattern.new(
        ".github/workflows/foo.yaml@main",
        owner: @org
      )

      assert_predicate instance, :invalid?
      assert_includes instance.errors[:base], 'Workflow ".github/workflows/foo.yaml@main" must be scoped to an owner/repo. Format should be: owner/repo/path/to/workflow.yaml@ref'
    end

    test "validates that the ref is not a short 7 character sha" do
      Repository.any_instance
        .stubs(:ref_to_sha)
        .with("e83c516")
        .returns("e83c5163316f89bfbde7d9ab23ca2e25604af290")

      GitRPC::Client.any_instance
        .stubs(:read_qualified_refs)
        .with(["refs/heads/e83c516", "refs/tags/e83c516"])
        .returns([["refs/heads/e83c516", nil], ["refs/tags/e83c516", nil]])

      instance = Actions::WorkflowPattern.new(
        "octo-org/octo-repo/.github/workflows/foo.yaml@e83c516",
        owner: @org
      )

      assert_predicate instance, :invalid?
      assert_includes instance.errors[:base], 'Workflow "octo-org/octo-repo/.github/workflows/foo.yaml@e83c516" looks like it\'s pinned to a short SHA. Please specify the full SHA.'
    end

    test "validates that the ref is not a partial sha" do
      Repository.any_instance
        .stubs(:ref_to_sha)
        .with("e83c5163316f89bfbde7")
        .returns("e83c5163316f89bfbde7d9ab23ca2e25604af290")

      GitRPC::Client.any_instance
        .stubs(:read_qualified_refs)
        .with(["refs/heads/e83c5163316f89bfbde7", "refs/tags/e83c5163316f89bfbde7"])
        .returns([["refs/heads/e83c5163316f89bfbde7", nil], ["refs/tags/e83c5163316f89bfbde7", nil]]) # main is a tag

      instance = Actions::WorkflowPattern.new(
        "octo-org/octo-repo/.github/workflows/foo.yaml@e83c5163316f89bfbde7",
        owner: @org
      )

      assert_predicate instance, :invalid?
      assert_includes instance.errors[:base], 'Workflow "octo-org/octo-repo/.github/workflows/foo.yaml@e83c5163316f89bfbde7" looks like it\'s pinned to a short SHA. Please specify the full SHA.'
    end

    test "validates that the repo exists under the owning org" do
      instance = Actions::WorkflowPattern.new(
        "octo-org/rando-repo/.github/workflows/foo.yaml@main",
        owner: @org
      )

      assert_predicate instance, :invalid?
      assert_includes instance.errors[:base], 'Workflow "octo-org/rando-repo/.github/workflows/foo.yaml@main" is well-formed but does not resolve to a file in any repository you can access.'
    end

    test "validates that the org exists under the owning org" do
      instance = Actions::WorkflowPattern.new(
        "rando-org/octo-repo/.github/workflows/foo.yaml@main",
        owner: @org
      )

      assert_predicate instance, :invalid?
      assert_includes instance.errors[:base], 'Workflow "rando-org/octo-repo/.github/workflows/foo.yaml@main" is well-formed but does not resolve to a file in any repository you can access.'
    end

    test "validates that the repo exists under the owning enterprise" do
      instance = Actions::WorkflowPattern.new(
        "rando-org/octo-repo/.github/workflows/foo.yaml@main",
        owner: @enterprise
      )

      assert_predicate instance, :invalid?
      assert_includes instance.errors[:base], 'Workflow "rando-org/octo-repo/.github/workflows/foo.yaml@main" is well-formed but does not resolve to a file in any repository you can access.'
    end

    test "is valid when provided an existing tag, with an existing repo, visible to the owner org" do
      Repository.any_instance
        .stubs(:ref_to_sha)
        .with("main")
        .returns("e83c5163316f89bfbde7d9ab23ca2e25604af290")

      GitRPC::Client.any_instance
        .stubs(:read_qualified_refs)
        .with(["refs/heads/main", "refs/tags/main"])
        .returns([["refs/heads/main", nil], ["refs/tags/main", "e83c5163316f89bfbde7d9ab23ca2e25604af290"]]) # main is a tag

      Actions::ParsedWorkflow
        .stubs(:parse_from_yaml)
        .with(@org_repo, ".github/workflows/foo.yaml", "e83c5163316f89bfbde7d9ab23ca2e25604af290")
        .returns(build(:parsed_workflow))

      Repository.any_instance
        .stubs(:is_commit_in_branch_or_tag?)
        .with("e83c5163316f89bfbde7d9ab23ca2e25604af290")
        .returns(true)

      instance = Actions::WorkflowPattern.new(
        "octo-org/octo-repo/.github/workflows/foo.yaml@main",
        owner: @org
      )

      assert_predicate instance, :valid?
      assert_empty instance.errors
    end

    test "is valid when provided an existing tag, with an existing repo, visible to the owner enterprise" do
      Repository.any_instance
        .stubs(:ref_to_sha)
        .with("main")
        .returns("e83c5163316f89bfbde7d9ab23ca2e25604af290")

      GitRPC::Client.any_instance
        .stubs(:read_qualified_refs)
        .with(["refs/heads/main", "refs/tags/main"])
        .returns([["refs/heads/main", nil], ["refs/tags/main", "e83c5163316f89bfbde7d9ab23ca2e25604af290"]]) # main is a tag

      Actions::ParsedWorkflow
        .stubs(:parse_from_yaml)
        .with(@org_repo, ".github/workflows/foo.yaml", "e83c5163316f89bfbde7d9ab23ca2e25604af290")
        .returns(build(:parsed_workflow))

      Repository.any_instance
        .stubs(:is_commit_in_branch_or_tag?)
        .with("e83c5163316f89bfbde7d9ab23ca2e25604af290")
        .returns(true)

      instance = Actions::WorkflowPattern.new(
        "octo-org/octo-repo/.github/workflows/foo.yaml@main",
        owner: @enterprise
      )

      assert_predicate instance, :valid?
      assert_empty instance.errors
    end

    test "validates no ref provided" do
      instance = Actions::WorkflowPattern.new(
        "octo-org/octo-repo/.github/workflows/foo.yaml@main",
        owner: @enterprise
      )

      assert_predicate instance, :invalid?
      assert_includes instance.errors[:base], 'Specified ref, tag, or SHA "main" was not found for workflow "octo-org/octo-repo/.github/workflows/foo.yaml@main".'
    end

    test "validates ref is not ambiguous" do
      Repository.any_instance
        .stubs(:ref_to_sha)
        .with("main")
        .returns("e83c5163316f89bfbde7d9ab23ca2e25604af290")

      GitRPC::Client.any_instance
        .stubs(:read_qualified_refs)
        .with(["refs/heads/main", "refs/tags/main"])
        .returns([["refs/heads/main", "e83c5163316f89bfbde7d9ab23ca2e25604af290"], ["refs/tags/main", "e83c5163316f89bfbde7d9ab23ca2e25604af290"]]) # main is a tag

      instance = Actions::WorkflowPattern.new(
        "octo-org/octo-repo/.github/workflows/foo.yaml@main",
        owner: @enterprise
      )

      assert_predicate instance, :invalid?
      assert_nil instance.disambiguated_ref
      assert_includes instance.errors[:base], 'Provided ref "main" is ambiguous for workflow "octo-org/octo-repo/.github/workflows/foo.yaml@main". Please clarify whether the ref refers to a branch or a tag, e.g. "refs/heads/main" or "refs/tags/main".'
    end

    test "validates ref is reachable" do
      Repository.any_instance
        .stubs(:ref_to_sha)
        .with("e83c5163316f89bfbde7d9ab23ca2e25604af290")
        .returns("e83c5163316f89bfbde7d9ab23ca2e25604af290")

      Repository.any_instance
        .stubs(:is_commit_in_branch_or_tag?)
        .with("e83c5163316f89bfbde7d9ab23ca2e25604af290")
        .returns(false) # commit is *not* reachable

      instance = Actions::WorkflowPattern.new(
        "octo-org/octo-repo/.github/workflows/foo.yaml@e83c5163316f89bfbde7d9ab23ca2e25604af290",
        owner: @enterprise
      )

      assert_predicate instance, :invalid?
      assert_includes instance.errors[:base], 'Provided ref "e83c5163316f89bfbde7d9ab23ca2e25604af290" does not resolve to a commit for workflow "octo-org/octo-repo/.github/workflows/foo.yaml@e83c5163316f89bfbde7d9ab23ca2e25604af290"'
    end

    test "disambiguates ref to tag" do
      Repository.any_instance
        .stubs(:ref_to_sha)
        .with("main")
        .returns("e83c5163316f89bfbde7d9ab23ca2e25604af290")

      GitRPC::Client.any_instance
        .stubs(:read_qualified_refs)
        .with(["refs/heads/main", "refs/tags/main"])
        .returns([["refs/heads/main", nil], ["refs/tags/main", "e83c5163316f89bfbde7d9ab23ca2e25604af290"]]) # main is a tag

      instance = Actions::WorkflowPattern.new(
        "octo-org/octo-repo/.github/workflows/foo.yaml@main",
        owner: @enterprise
      )

      Actions::ParsedWorkflow
        .stubs(:parse_from_yaml)
        .with(@org_repo, ".github/workflows/foo.yaml", "e83c5163316f89bfbde7d9ab23ca2e25604af290")
        .returns(build(:parsed_workflow))

      Repository.any_instance
        .stubs(:is_commit_in_branch_or_tag?)
        .with("e83c5163316f89bfbde7d9ab23ca2e25604af290")
        .returns(true)

      assert_predicate instance, :valid?
      assert_equal "octo-org/octo-repo/.github/workflows/foo.yaml@refs/tags/main", instance.disambiguated_ref
      assert_empty instance.errors[:base]
    end

    test "disambiguates ref to branch" do
      Repository.any_instance
        .stubs(:ref_to_sha)
        .with("main")
        .returns("e83c5163316f89bfbde7d9ab23ca2e25604af290")

      GitRPC::Client.any_instance
        .stubs(:read_qualified_refs)
        .with(["refs/heads/main", "refs/tags/main"])
        .returns([["refs/heads/main", "e83c5163316f89bfbde7d9ab23ca2e25604af290"], ["refs/heads/main", nil]]) # main is a branch

      instance = Actions::WorkflowPattern.new(
        "octo-org/octo-repo/.github/workflows/foo.yaml@main",
        owner: @enterprise
      )

      Actions::ParsedWorkflow
        .stubs(:parse_from_yaml)
        .with(@org_repo, ".github/workflows/foo.yaml", "e83c5163316f89bfbde7d9ab23ca2e25604af290")
        .returns(build(:parsed_workflow))

      Repository.any_instance
        .stubs(:is_commit_in_branch_or_tag?)
        .with("e83c5163316f89bfbde7d9ab23ca2e25604af290")
        .returns(true)

      assert_predicate instance, :valid?
      assert_equal "octo-org/octo-repo/.github/workflows/foo.yaml@refs/heads/main", instance.disambiguated_ref
      assert_empty instance.errors[:base]
    end

    test "disambiguates ref to tag when full tag ref is provided" do
      Repository.any_instance
        .stubs(:ref_to_sha)
        .with("refs/tags/main")
        .returns("e83c5163316f89bfbde7d9ab23ca2e25604af290")

      instance = Actions::WorkflowPattern.new(
        "octo-org/octo-repo/.github/workflows/foo.yaml@refs/tags/main",
        owner: @enterprise
      )

      Actions::ParsedWorkflow
        .stubs(:parse_from_yaml)
        .with(@org_repo, ".github/workflows/foo.yaml", "e83c5163316f89bfbde7d9ab23ca2e25604af290")
        .returns(build(:parsed_workflow))

      Repository.any_instance
        .stubs(:is_commit_in_branch_or_tag?)
        .with("e83c5163316f89bfbde7d9ab23ca2e25604af290")
        .returns(true)

      assert_predicate instance, :valid?
      assert_equal "octo-org/octo-repo/.github/workflows/foo.yaml@refs/tags/main", instance.disambiguated_ref
      assert_empty instance.errors[:base]
    end

    test "disambiguates ref to branch when full branch ref is provided" do
      Repository.any_instance
        .stubs(:ref_to_sha)
        .with("refs/heads/main")
        .returns("e83c5163316f89bfbde7d9ab23ca2e25604af290")

      instance = Actions::WorkflowPattern.new(
        "octo-org/octo-repo/.github/workflows/foo.yaml@refs/heads/main",
        owner: @enterprise
      )

      Actions::ParsedWorkflow
        .stubs(:parse_from_yaml)
        .with(@org_repo, ".github/workflows/foo.yaml", "e83c5163316f89bfbde7d9ab23ca2e25604af290")
        .returns(build(:parsed_workflow))

      Repository.any_instance
        .stubs(:is_commit_in_branch_or_tag?)
        .with("e83c5163316f89bfbde7d9ab23ca2e25604af290")
        .returns(true)

      assert_predicate instance, :valid?
      assert_equal "octo-org/octo-repo/.github/workflows/foo.yaml@refs/heads/main", instance.disambiguated_ref
      assert_empty instance.errors[:base]
    end

    test "disambiguates ref to branch when full SHA is provided" do
      Repository.any_instance
        .stubs(:ref_to_sha)
        .with("e83c5163316f89bfbde7d9ab23ca2e25604af290")
        .returns("e83c5163316f89bfbde7d9ab23ca2e25604af290")

      instance = Actions::WorkflowPattern.new(
        "octo-org/octo-repo/.github/workflows/foo.yaml@e83c5163316f89bfbde7d9ab23ca2e25604af290",
        owner: @enterprise
      )

      Actions::ParsedWorkflow
        .stubs(:parse_from_yaml)
        .with(@org_repo, ".github/workflows/foo.yaml", "e83c5163316f89bfbde7d9ab23ca2e25604af290")
        .returns(build(:parsed_workflow))

      Repository.any_instance
        .stubs(:is_commit_in_branch_or_tag?)
        .with("e83c5163316f89bfbde7d9ab23ca2e25604af290")
        .returns(true)

      assert_predicate instance, :valid?
      assert_equal "octo-org/octo-repo/.github/workflows/foo.yaml@e83c5163316f89bfbde7d9ab23ca2e25604af290", instance.disambiguated_ref
      assert_empty instance.errors[:base]
    end

    # annotated tags have a different OID than the commit it points to
    test "handles annotated tags" do

      annotated_tag = "refs/tags/my_annotated_tag"
      annotated_tag_oid = "a83c5163316f89bfbde7d9ab23ca2e25604af290" # oid for the tag itself
      annotated_tag_commit_oid = "e83c5163316f89bfbde7d9ab23ca2e25604af290" # oid for the commit the tag points to

      Repository.any_instance
        .stubs(:ref_to_sha)
        .returns(annotated_tag_commit_oid)

      instance = Actions::WorkflowPattern.new(
        "octo-org/octo-repo/.github/workflows/foo.yaml@#{annotated_tag}",
        owner: @enterprise
      )
      # will find workflow at annotated tag's commit oid
      Actions::ParsedWorkflow
        .stubs(:parse_from_yaml)
        .with(@org_repo, ".github/workflows/foo.yaml", annotated_tag_commit_oid)
        .returns(build(:parsed_workflow))

      Repository.any_instance
        .stubs(:is_commit_in_branch_or_tag?)
        .with("e83c5163316f89bfbde7d9ab23ca2e25604af290")
        .returns(true)

      assert_predicate instance, :valid?
      assert_equal "octo-org/octo-repo/.github/workflows/foo.yaml@#{annotated_tag}", instance.disambiguated_ref
      assert_empty instance.errors[:base]
    end

    test "handles OID SHAs that aren't commits gracefully" do
      Repository.any_instance
        .stubs(:ref_to_sha)
        .with("e83c5163316f89bfbde7d9ab23ca2e25604af290")
        .returns("e83c5163316f89bfbde7d9ab23ca2e25604af290")

      instance = Actions::WorkflowPattern.new(
        "octo-org/octo-repo/.github/workflows/foo.yaml@e83c5163316f89bfbde7d9ab23ca2e25604af290",
        owner: @enterprise
      )

      Repository.any_instance
        .stubs(:is_commit_in_branch_or_tag?)
        .with("e83c5163316f89bfbde7d9ab23ca2e25604af290")
        .raises(GitRPC::InvalidObject.new)

      assert_predicate instance, :invalid?
      assert_includes instance.errors[:base], 'Provided ref "e83c5163316f89bfbde7d9ab23ca2e25604af290" does not resolve to a commit object.'
    end

    test "handles case-insensitive owner name matches" do
      Repository.any_instance
        .stubs(:ref_to_sha)
        .with("main")
        .returns("e83c5163316f89bfbde7d9ab23ca2e25604af290")

      GitRPC::Client.any_instance
        .stubs(:read_qualified_refs)
        .with(["refs/heads/main", "refs/tags/main"])
        .returns([["refs/heads/main", nil], ["refs/tags/main", "e83c5163316f89bfbde7d9ab23ca2e25604af290"]]) # main is a tag

      Actions::ParsedWorkflow
        .stubs(:parse_from_yaml)
        .with(@org_repo, ".github/workflows/foo.yaml", "e83c5163316f89bfbde7d9ab23ca2e25604af290")
        .returns(build(:parsed_workflow))

      Repository.any_instance
        .stubs(:is_commit_in_branch_or_tag?)
        .with("e83c5163316f89bfbde7d9ab23ca2e25604af290")
        .returns(true)

      instance = Actions::WorkflowPattern.new(
        "OCTO-ORG/octo-repo/.github/workflows/foo.yaml@main",
        owner: @org
      )

      assert_predicate instance, :valid?
      assert_empty instance.errors
    end
  end
end
