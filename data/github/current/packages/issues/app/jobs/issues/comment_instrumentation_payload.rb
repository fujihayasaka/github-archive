# typed: true
# frozen_string_literal: true

module Issues
  class CommentInstrumentationPayload
    class CommentInstrumentationPayloadError < StandardError; end

    def initialize(actor:, repository:, comment_type:)
      @actor = actor
      @repository = repository
      @comment_type = comment_type
    end

    def payload
      payload = {
        dimensions: dimensions,
        measures: measures,
        context: {},
      }

      payload.each_value do |hash|
        hash.delete_if { |_, value| value.nil? }
      end

      payload
    end

    private

    def contributors_count(committed_since)
      ActiveRecord::Base.connected_to(role: :reading) do
        CommitContributions.domain.contributors_count_for_repository(@repository, since: committed_since)
      end
    end

    def dimensions
      result = {
        "actor_id" => @actor.id,
        "actor_login" => @actor.login,
        "comment_type" => @comment_type,
        "repository_id" => @repository.id.to_s,
        "repository_name" => @repository.name,
        "repository_public" => @repository.public?.to_s,
      }

      if @repository.owner
        result["repository_owner_type"] = @repository.owner.class.name.downcase
        result["repository_owner_id"] = @repository.owner.id.to_s
        result["repository_owner_login"] = @repository.owner.login
      end

      result
    end

    def measures
      repository_issues_count = @repository.issues.not_spammy.count

      result = {
        "repository_all_forks_count" => @repository.all_forks_count,
        "repository_issues_count" => repository_issues_count,
        "repository_issues_open_count" => @repository.open_issues_count,
        "repository_issues_thirty_day_updated_count" => @repository.issues.not_spammy.since(30.days.ago).count,
        "repository_public_forks_count" => @repository.public_fork_count,
        "repository_stars_count" => @repository.stargazer_count,
        "repository_watchers_count" => @repository.watchers.count,
        "repository_code_contributors_thirty_day_count" => contributors_count(30.days.ago),
      }

      begin
        contributors = Contributors.new(@repository).count
        if contributors.computed?
          result["repository_contributors_count"] = contributors.value.to_s
        end
      rescue GitRPC::Timeout => expired
        GitHub.logger.error(
          "timeout while counting contributors",
          {
            exception: expired,
            "code.namespace": "App::Jobs::Issues::CommentInstrumentationPayload",
            "code.function": "measures"
          }
        )
      end

      result
    end
  end
end
