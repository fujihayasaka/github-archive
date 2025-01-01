# typed: true
# frozen_string_literal: true

module AdvisoryDB
  class AdvisoryImprovementPullRequestCreator
    class AdvisoriesRepositoryError < StandardError; end

    attr_reader :advisory

    def initialize(user, advisory, form)
      @user = user
      @advisory = advisory
      @form = form
    end

    def create_or_update_pull_request!
      validate_advisories_repository
      create_commit
      pull_request = update_pr || create_pr
      # Adds a job to add comment to a community contribution pull request to notify the
      # publisher of a repository advisory (if they still have write access to the it)
      # that a community contribution was submitted to modify the global advisory.
      NotifyAuthorCommunityAdvisoriesContributionJob.perform_later(pull_request, advisory, publisher_login)
      pull_request
    end

    private

    def advisories_repository
      @advisories_repository ||= AdvisoryDB.advisories_repository
    end

    def publisher_login
      repository_advisory = advisory.repository_advisory
      return unless repository_advisory && repository_advisory.publisher
      repository_advisory.writable_by?(repository_advisory.publisher) ? repository_advisory.publisher.login : nil
    end

    def create_commit
      metadata = {
        message: "Improve #{advisory.ghsa_id}",
        committer: @user,
        author: @user,
      }

      security_advisory_serializer = AdvisoryDB::SecurityAdvisorySerializer.new(advisory, @form)

      ref.append_commit(metadata, @user) do |changes|
        changes.add(
          AdvisoryDB.repo_file_path(advisory),
          security_advisory_serializer.create_advisory_file_content
        )
      end
    end

    def create_pr
      PullRequest.create_for!(advisories_repository, {
        user: @user,
        base: advisories_repository.default_branch,
        head: ref.name,
        title: "[#{advisory.ghsa_id}] #{AdvisoryDB::advisory_title(advisory)}",
        body: "**Updates**\n- #{@form.changed_human_attributes.sort.join("\n- ")}\n\n**Comments**\n#{@form.justification}",
      })
    end

    def ref
      return @ref if defined?(@ref)

      branch_name = "#{@user.login}-#{advisory.ghsa_id}"
      @ref = advisories_repository.heads.find(branch_name) || advisories_repository.heads.create(branch_name, advisories_repository.default_branch_ref.target_oid, @user)
    end

    def update_pr
      existing_pr = PullRequest.find_open_based_on_head_ref(advisories_repository.id, ref.name).first
      return unless existing_pr

      existing_pr.synchronize!(user: @user, repo: advisories_repository)
      existing_pr
    end

    def validate_advisories_repository
      unless advisories_repository
        raise AdvisoriesRepositoryError, "Does not exist: #{AdvisoryDB::ADVISORIES_REPOSITORY_NWO}"
      end

      unless advisories_repository.default_branch_ref
        raise AdvisoriesRepositoryError, "No initial commit for default branch: #{advisories_repository.default_branch}"
      end
    end
  end
end
