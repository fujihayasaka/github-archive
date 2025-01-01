# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class ConvertTeamDiscussionsToDiscussionsJob < ApplicationJob
  queue_as :convert_team_discussions_to_discussions
  retry_on_dirty_exit
  # Will generate a lock thats unique to the team and the repository (eg: team-2-repository-3-offset_id-4)
  locked_by timeout: 1.hour, key: ->(_job) { CONVERT_LOCK_PROC }

  CONVERT_LOCK_PROC = T.let(proc do |job|
    if job.arguments.empty?
      DEFAULT_LOCK_KEY
    else
      if job.arguments.is_a?(Array)
        job.arguments.first.except(:actor, :include_private).map { |k, v| "#{k}-#{v.id}" }.join("-")
      else
        DEFAULT_LOCK_PROC.call(job)
      end
    end
  end, T.proc.params(arg0: T.class_of(ConvertTeamDiscussionsToDiscussionsJob)).returns(String))

  MAX_TRIES = 3

  retry_on(
    StandardError,
    TeamPostToDiscussionConversionVerifier::MissingCommentsError,
    wait: :polynomially_longer,
    attempts: MAX_TRIES,
  )

  BATCH_SIZE = 100

  # public: Convert all the team posts in the given team to discussions in the given repository.
  # actor: User who is performing this
  # repository: Repository to create the discussions in
  # offset_id: Integer of the last post id converted
  # include_private: Boolean indicating if private posts should be included in the conversion or not (default: true)
  sig do
    params(
      actor: User,
      team: Team,
      repository: Repository,
      offset_id: Integer,
      include_private: T::Boolean,
    ).void
  end
  def perform(actor:, team:, repository:, offset_id: 0, include_private: true)
    # Push data to make it easier to find exceptions in Sentry
    Failbot.push(team_id: team.id, repository_id: repository.id)

    ActiveRecord::Base.connected_to(role: :reading) do
      query = team.discussion_posts.where("id > ?", offset_id)
      query = query.where(private: false) unless include_private
      batch = query.limit(BATCH_SIZE).order(:id)

      if batch.size > 0
        DiscussionPost.throttle do
          batch.each do |post|
            ActiveRecord::Base.connected_to(role: :writing) do
              convert_team_post_to_discussion(post, actor: actor, repository: repository)
            end
          end
        end
      end

      unless batch.size < BATCH_SIZE
        ConvertTeamDiscussionsToDiscussionsJob.perform_later(actor: actor, team: team, repository: repository,
          offset_id: batch.last!.id, include_private: include_private)
      end
    end

    team_discussions_query = DiscussionPost.where(team_id: team.id)
    team_discussions_query = team_discussions_query.where(private: false) unless include_private

    finished = T.let(true, T::Boolean)
    team_discussions_query.each do |team_discussion|
      unless team_discussion.discussion.present?
        finished = false
        break
      end
    end

    if finished
      ActiveRecord::Base.connected_to(role: :writing) do
        team.update(migration_complete: true)

        repo_info = "Team Discussions: #{team.organization}/#{repository.name}"
        if team.description.present?
          punctuation = team.description.match?(/[[:punct:]]$/) ? " " : ". "
          description = team.description + punctuation + repo_info
        else
          description = repo_info
        end

        team.update(description: description)
      end
    end
  end

  private

  sig { params(post: DiscussionPost, actor: User, repository: Repository).returns(T::Boolean) }
  def convert_team_post_to_discussion(post, actor:, repository:)
    converter = TeamPostToDiscussionConverter.new(post, actor: actor, repository: repository)
    return false unless converter.prepare_for_conversion
    converter.finish_conversion
  end
end
