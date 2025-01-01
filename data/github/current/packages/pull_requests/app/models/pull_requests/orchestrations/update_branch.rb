# typed: true
# frozen_string_literal: true

class PullRequests::Orchestrations::UpdateBranch < PullRequestOrchestration
  class UpdateMethod < T::Enum
    enums do
      Rebase = new("rebase")
      Merge = new("merge")
      Invalid = new("invalid")
    end

    sig { params(input: String).returns(UpdateMethod) }
    def deserialize(input)
      case input
      when "rebase"
        Rebase
      when "merge"
        Merge
      else
        Invalid
      end
    end
  end

  job_start

  step :create_new_head_ref, skip: true do
    return unless pull_request = self.pull_request
    return unless head_repository = pull_request.head_repository
    return unless user = self.user
    return unless new_head_ref = data[:new_head_ref]

    unless head_repository.writable_by?(user)
      return [:failed, "Head repository not writable by user"]
    end

    head_repository.heads.create(new_head_ref, data[:expected_head_oid], user)
    pull_request.head_ref = new_head_ref
    pull_request.save!
    pull_request.synchronize!(user: user, repo: T.must(pull_request.repository))
    pull_request.reload
  end

  step :update_branch do
    return unless pull_request = self.pull_request
    return unless user = self.user

    case update_method = UpdateMethod.deserialize(data[:update_method])
    when UpdateMethod::Rebase
      pull_request.rebase_head_on_base(
        user: user,
        author_email: user.default_author_email(pull_request.repository, pull_request.head_sha),
        expected_head_oid: data[:expected_head_oid],
      )
    when UpdateMethod::Merge
      resolve_conflicts = data[:resolve_conflicts]&.each_with_object({}) { |(filename, contents), result| result[CGI.unescape(filename)] = contents } || nil

      pull_request.merge_base_into_head(
        user: user,
        author_email: user.default_author_email(pull_request.repository, pull_request.head_sha),
        base_oid: data[:base_oid],
        expected_head_oid: data[:expected_head_oid],
        resolve_conflicts:,
      )
    when UpdateMethod::Invalid
      [:failed, "unkown merge method"]
    else
      T.absurd(update_method)
    end
  rescue GitHub::UIError => e
    [:skipped, e.ui_message]
  rescue Git::Ref::RepositoryRuleViolationError => e
    [:failed, e.detailed_message]
  end

  on_end_orchestration do |_, error_klass|
    T.bind(self, PullRequests::Orchestrations::UpdateBranch)
    return unless pull_request = self.pull_request
    return unless running? && error_klass.present?

    GitHub.dogstats.increment("pull_request.update_branch.uncaught_expection")
    # If we've reached this point we've hit an uncaught exception in the background
    # job so we should default to failing so we don't block future update operations.
    self.state = :failed
    self.error_message = "An unknown error occured. Please try again."
    self.save!
  end
end
