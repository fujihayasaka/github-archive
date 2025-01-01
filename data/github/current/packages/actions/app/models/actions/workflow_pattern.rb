# typed: true
# frozen_string_literal: true

class Actions::WorkflowPattern
  include ActiveModel::Validations

  attr_accessor :owner, :raw_pattern, :ref, :disambiguated_ref

  validates_presence_of :raw_pattern
  validates_presence_of :owner
  validate :validate_pattern

  def initialize(raw_pattern, owner:)
    self.raw_pattern = raw_pattern
    self.owner = owner
  end

  private def validate_pattern
    if raw_pattern.start_with?(".github/workflows/", ".github/workflows-lab/")
      errors.add :base, unscoped_workflow
      return false
    end

    owner_name, repo_name, path_at_ref = raw_pattern.split("/", 3)

    if [owner_name, repo_name, path_at_ref].any?(&:blank?)
      errors.add :base, pattern_malformed
      return false
    end

    path, matched_ref = path_at_ref.match(/\A(.*)@([^@]+)\z/)&.captures
    self.ref = matched_ref

    if ref.blank?
      errors.add :base, ref_not_provided
      return false
    end

    organization = owner.is_a?(Organization) ? owner : owner.organizations.find_by_login(owner_name)

    # org runner_groups can't be restricted to workflows from other orgs
    if owner.is_a?(Organization) && !owner.login.casecmp?(owner_name)
      errors.add :base, workflow_not_found
      return false
    end

    # enterprise runner_groups must be restricted to workflows within its own orgs
    if owner.is_a?(Business) && !organization
      errors.add :base, workflow_not_found
      return false
    end

    repository = organization.repositories.find_by(name: repo_name)
    if !repository
      errors.add :base, workflow_not_found
      return false
    end

    full_ref, resolved_commit = disambiguate_ref(ref, repository)
    self.disambiguated_ref = build_disambiguated_ref(owner_name, repo_name, path, full_ref) if full_ref

    if !resolved_commit
      errors.add :base, ref_not_found
      return false
    end

    # Actions doesn't support Short SHAs
    if resolved_commit.starts_with?(ref) && !GitRPC::Util.valid_full_oid?(ref)
      errors.add :base, no_short_shas
      return false
    end

    # ensure ref is not ambiguous
    if !disambiguated_ref
      errors.add :base, ambiguous_ref
      return false
    end

    begin
      if !repository.is_commit_in_branch_or_tag?(resolved_commit)
        errors.add :base, unreachable_commit
        return false
      end
    rescue GitRPC::InvalidObject
      # If a user passes a OID SHA which is _not_ a commit object (e.g. a tree
      # or tag), we won't be able to peel it nor verify whether it is
      # reachable.
      errors.add :base, invalid_object
      return false
    end

    parsed_workflow_at_ref = Actions::ParsedWorkflow.parse_from_yaml(repository, path, resolved_commit)
    if !parsed_workflow_at_ref
      errors.add :base, workflow_not_found_at_ref
      false
    end
  end

  # @return Array(String?, String?)
  # If the user gives us "foo.yaml@v2", the ref "v2" could refer to either a tag ("refs/tags/v2") or a branch ("refs/heads/v2").
  # This methods tries to resolve a ref as a tag and a branch, and returns a 2-tuple of (full resolved tag/branch or nil, full commit oid at tag/branch).
  private def disambiguate_ref(ref, repository)

    # resolve commit. this will peel even annotated tags to the commit they point to, so we need to return this
    resolved_commit = repository.ref_to_sha(ref)

    # if the commits doesn't exist at all, just return
    return nil, nil if resolved_commit.nil?

    # we have a valid commit, we just need to figure out where it came from
    given_specific_ref = ref.starts_with?("refs/heads/") || ref.starts_with?("refs/tags/") || GitRPC::Util.valid_full_oid?(ref)

    # if the ref was already fully qualified (refs/tags/foo, refs/heads/foo, SHA), we can return it
    return ref, resolved_commit if given_specific_ref

    # we know the ref exists, but we need to figure out if it is a tag, branch, or short SHA
    full_tag = "refs/tags/#{ref}"
    full_branch = "refs/heads/#{ref}"

    (_, commit_from_branch), (_, commit_from_tag) = repository.resolve_references([full_branch, full_tag], source: :workflow_pattern)

    # if the tag resolves and not the branch, return the tag
    return full_tag, resolved_commit if commit_from_tag && !commit_from_branch

    # if the branch resolves and not the tag, return the branch
    return full_branch, resolved_commit if !commit_from_tag && commit_from_branch

    # neither the branch or the tag exists, but since the refs DOES exist, it is either a short SHA or ambiguous
    # in the ambiguous case, resolved_commit might be the branch or the tag, but we fail validation when disambiguated_ref is nil
    [nil, resolved_commit]
  end

  private def build_disambiguated_ref(owner_name, repo, path, full_ref)
    path_at_ref = "#{path}@#{full_ref}"
    [owner_name, repo, path_at_ref].join("/")
  end

  # Error message builders below

  private def unscoped_workflow
    "Workflow \"#{raw_pattern}\" must be scoped to an owner/repo. Format should be: owner/repo/path/to/workflow.yaml@ref"
  end

  private def no_short_shas
    "Workflow \"#{raw_pattern}\" looks like it's pinned to a short SHA. Please specify the full SHA."
  end

  private def pattern_malformed
    "Workflow \"#{raw_pattern}\" is malformed. Format should be: owner/repo/path/to/workflow.yaml@ref"
  end

  private def ref_not_found
    "Specified ref, tag, or SHA \"#{ref}\" was not found for workflow \"#{raw_pattern}\"."
  end

  private def ref_not_provided
    "Workflow \"#{raw_pattern}\" must be pinned to a ref, tag, or full SHA."
  end

  private def workflow_not_found
    "Workflow \"#{raw_pattern}\" is well-formed but does not resolve to a file in any repository you can access."
  end

  private def workflow_not_found_at_ref
    "Workflow \"#{raw_pattern}\" does not exist at the ref \"#{ref}\"."
  end

  private def ambiguous_ref
    "Provided ref \"#{ref}\" is ambiguous for workflow \"#{raw_pattern}\". Please clarify whether the ref refers to a branch or a tag, e.g. \"refs/heads/main\" or \"refs/tags/main\"."
  end

  private def unreachable_commit
    "Provided ref \"#{ref}\" does not resolve to a commit for workflow \"#{raw_pattern}\""
  end

  private def invalid_object
    "Provided ref \"#{ref}\" does not resolve to a commit object."
  end
end
