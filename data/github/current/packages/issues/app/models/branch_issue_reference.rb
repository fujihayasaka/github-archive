# typed: true
# frozen_string_literal: true

# Associates an Issue to a branch, where the `branch_name` is the name of a ref on the given Repository.
# The branch and the Issue can belong to different Repositories.
class BranchIssueReference < ApplicationRecord::Collab
  extend GitHub::Encoding
  force_utf8_encoding :branch_name

  belongs_to :issue
  belongs_to :creator, class_name: "User"
  belongs_to :issue_repository, class_name: "Repository"
  belongs_to :branch_repository, class_name: "Repository"

  before_validation :set_issue_repository

  validates :issue, :branch_name, :creator, :issue_repository, :branch_repository, presence: true
  validates :branch_name, uniqueness: { scope: [:issue_id, :branch_repository_id] }

  scope :by_issue, ->(issue) { where(issue_id: issue) }

  scope :by_branch_name, ->(branch_name) { where(branch_name: branch_name) }

  scope :by_repo, ->(repo) { where(branch_repository_id: repo) }

  scope :by_user, ->(user) { where(creator_id: user) }

  class SourceBranchNotFound < StandardError
    attr_accessor :branch_name
    def initialize(branch_name)
      @branch_name = branch_name
    end

    def message
      "Sorry, the source branch #{branch_name} could not be found."
    end
  end

  # Finds the first reference in the given repo for the given branch name.
  # Note it's possible for multiple references to exist for the same branch name,
  # but this should be very unlikely. If that happens we'll return the newest one.
  def self.by_repo_and_branch(repository, branch_name)
    branch_name_with_prefix = "refs/heads/#{branch_name}"
    where(branch_repository_id: repository.id, branch_name: [branch_name, branch_name_with_prefix]).order(id: :desc).first
  end

  # Enqueue a job to destroy any relevent BranchIssueReferences for the given repo and branch name.
  def self.destroy_in_background(repository:, branch_name:)
    DestroyBranchIssueReferencesJob.perform_later(repository.id, branch_name)
  end

  # Check if the given user can create a branch for this Issue.
  # This method exists to centralize the logic and make it easier to test.
  # These checks should go from fastest->slowest
  def self.creatable_for?(user:, issue:, repository:)
    !issue.pull_request? && repo_writable?(user: user, repo: repository)
  end

  # Returns an array of BranchIssueReferences, not an ActiveRecord::Relation
  def self.viewable_by(user:, issue:)
    BranchIssueReference
      .by_issue(issue)
      .includes(:branch_repository, :issue_repository)
      .order(:branch_name)
      .select { |ref| ref.repository.readable_by?(user) && !ref.repository.spammy? }
  end

  def self.for_repo(repository:)
    where(branch_repository_id: repository.id).order(:branch_name)
  end

  def self.async_filtered_branch_issue_references_for(viewer:, issue:)
    references = BranchIssueReference.by_issue(issue)
    Promise.all(references.map(&:async_branch_repository)).then do |repositories|
      repositories = repositories.compact.index_by(&:id)
      load_accessible_branch_references = references.map do |reference|
        repo = repositories[reference.branch_repository_id]
        next if !repo || (repo.spammy? && !viewer&.site_admin?)

        readable_promise = repo.public? ? Promise.resolve(true) : repo.resources.contents.async_readable_by?(viewer)
        readable_promise.then do |readable|
          next if !readable
          next reference
        end
      end

      Promise.all(load_accessible_branch_references).then do |accessible_references|
        accessible_references.compact
      end
    end
  end

  # We need to use this criteria to filter repos in the TargetRepositoryController as well
  def self.repo_writable?(user:, repo:)
    repo.writable_by?(user) &&
    !repo.empty? &&
    repo.writable?
  end

  # Returns a possible branch name for the given issue based on the issue's title and number.
  # If the name already exists, it will append a number to the end of the name
  def self.candidate_branch_name(issue:, repository: nil)
    repository ||= issue.repository

    issue_title = issue.title.dup

    # The {Emoji} class also matches digits, while {Extended_Pictographic} alone does not match skin tone
    # modifiers that trail behind the emoji,
    # see https://stackoverflow.com/questions/64389323/why-do-unicode-emoji-property-escapes-match-numbers
    issue_title.gsub!(/[\p{Extended_Pictographic}\u{1F3FB}-\u{1F3FF}\u{1F9B0}-\u{1F9B3}]/, "")
    issue_title.gsub!(/\-/, " ")                          # replace dashes with spaces to be normalized below
    issue_title.gsub!(/[^\_[^\`\p{Punct}]]/, "")          # remove punctuation except underscores
    issue_title.gsub!(/[^[:print:]]/, "")                 # remove zero-width joiner/non-printable characters
    issue_title.gsub!(/[\uFE00-\uFE0F]/, "")              # remove variation characters used in some emojis
    issue_title.gsub!(/[<>]/, "")                         # remove angle brackets

    normalized_title = Git::Ref.normalize(issue_title)
    ideal_title = "#{issue.number}-#{normalized_title}".downcase
    heads = repository.heads

    if heads.include?(ideal_title)
      heads.temp_name(topic: ideal_title)
    else
      ideal_title
    end
  end

  # Creates a new branch in the given Repository. If that succeeds, it creates a BranchIssueReference.
  # Raises if the branch can't be created, and if the subsequent BranchIssueReference fails validation.
  def self.create_with_new_branch!(issue:, new_branch_name:, source_branch_name:, reflog_data:, repository:, creator:, commit_oid: nil)
    normalized_name = Git::Ref.normalize(new_branch_name)
    branch_issue_reference = create!(
      branch_name: normalized_name,
      branch_repository: repository,
      creator: creator,
      issue: issue,
    )
    commit_oid = T.let(commit_oid, T.nilable(String))

    begin
      log_payload = {
        "gh.issue.id": issue.id,
        "gh.repo.id": repository.id,
        "gh.issue.branch_name": normalized_name,
        "gh.issue.source_branch_name": source_branch_name,
        "gh.request_id": GitHub.context[:request_id]
      }
      GitHub.logger.with_named_tags(log_payload) do
        commit_oid ||= repository.ref_to_sha(source_branch_name)

        raise SourceBranchNotFound.new(source_branch_name) if commit_oid.nil?

        GitHub.logger.info("Creating branch", { "git.commit.oid": commit_oid })
        repository.heads.create(normalized_name, commit_oid, creator, reflog_data: reflog_data)
        branch_issue_reference
      end
    rescue StandardError => e
      # delete the BranchIssueReference if the branch can't be created
      branch_issue_reference.destroy!
      raise e
    end
  end

  # Links the new PullRequest to an Issue if there's an existing BranchIssueReference
  # for this PullRequest's branch. We do this by creating a manual CloseIssueReference
  #
  # This method is called synchronously from the UpdateCloseIssueReferenceJob, at the top of the job
  def self.link_pull_request(pull_request)
    branch_issue_reference = by_repo_and_branch(pull_request.repository, pull_request.head_ref_name)

    if branch_issue_reference
      # If this branch links to an issue, we'll go ahead
      # and link this PR to that issue.
      # According to this issue https://github.com/github/issues/issues/4620, BranchIssueRefereneces can wrongly
      # reference a pull request. In this case, we shouldn't create a CloseIssueReference.
      issue = Issue.find_by(id: branch_issue_reference.issue_id)
      unless issue&.pull_request?
        ref = pull_request.close_issue_references.build(
          issue: issue,
          source: :manual,
          actor_id: pull_request.user_id
        )

        ref.validate

        # sometimes, for an unknown reason, there already exists a close_issue_reference _and_ a
        # branch_issue_reference, in those cases, we fail to create a close_issue_reference due to
        # violating unique validators, but we still want to close the BranchIssueReference if it still
        # exists. We are aware of these erros but do not want to act on them, hence we skip saving.
        issue_exists = ref.errors.errors.find { |error| error.attribute == :issue_id && error.type == :taken }

        # If the actor does not have permissions to create the reference, then we should not create it.
        # This is not an issue we need to report to Sentry. See: https://github.com/github/issues/issues/3494.
        inaccessible = ref.errors.errors.find { |error| error.attribute == :actor_id && error.type == :inaccessible }

        unless issue_exists || inaccessible
          ref.save!
        end
      end

      # Once we've linked a PR to an issue,
      # having a link to the branch is superfluous.
      branch_issue_reference.destroy

      GitHub.dogstats.increment("branch_for_issue", tags: ["create_linked_pr:success"])
    end
  rescue StandardError => e # rubocop:todo Lint/GenericRescue
    GitHub.dogstats.increment("branch_for_issue", tags: ["create_linked_pr:error"])
    Failbot.report!(e)
  end

  # Until we can run a transition, references created before we allowed users to pick a different repo
  # for the branch will have a nil branch_repository.
  def repository
    branch_repository || issue_repository
  end

  def platform_type_name
    "LinkedBranch"
  end

  private

  def set_issue_repository
    self.issue_repository = issue&.repository
  end
end
