# typed: true
# frozen_string_literal: true

# This lib isn't used directly in this file,
# but not having it here seems to be contributing
# to or making github/github#66202 worse somehow
require "graphql/client"

require "sinatra/base"
unless defined? GitHub::Application
  require_relative "../../config/environment"
end

require "munger/client"

# The github/munger service is a github/github dependency, but runs as a 3rd
# party API service. In order to develop directly against it, the munger server
# has to be booted separately in development and run inside a Docker container.
#
# Developers not working directly on the topics feature probably don't want to
# do that, so this is a fake Sinatra API meant to emulate the munger service in
# development and supply fake topic data.
#
# If you want to actually develop against the github/munger server, boot
# github/github like so:
#
# MUNGER_URL=http://localhost:8000 bin/server
#
# Otherwise, running `bin/server` will use this fake API by default in
# development.
module Munger
  class FakeServer < Sinatra::Base
    get "/" do
      { message: "I'm aliiiiive" }.to_json
    end

    # jazz_user_repository_recommendations
    #
    # Response:
    #
    # { recommendations: [
    #    { repository_id: 123, // database ID of a valid Repository
    #      score: 0.5,         // random score between 0.0 and 1.0
    #      reason: "viewed",   // randomly chosen recommendation reason
    #      algorithm_version: "0.0.0", // hardcoded value
    #      generated_at: 1580239553 }  // Timestamp up to ten days ago
    #  ] }

    get "/features/jazz_user_repository_recommendations/:user_id" do
      return 404 unless User.exists?(id: params[:user_id])

      count = Integer(params.fetch(:per_page, 5))
      repos = Repository.where(public: true).order("id DESC").take(count)
      generated_at = (Time.now - rand(10).days).to_i

      {
        recommendations: repos.map do |repo|
          {
            repository_id: repo.id,
            score: rand,
            reason: RepositoryRecommendation.valid_reasons.sample,
            algorithm_version: "0.0.0",
            generated_at: generated_at,
          }
        end,
      }.to_json
    end

    # good_first_issues_for_repo_id
    #
    # Response:
    #
    # [ { issues: [
    #    { issue_id: 123,  // database ID of a valid Issue
    #      score: 0.5 }    // Random score between 0.0 and 1.0, ascending
    #  ] } ]

    get "/features/first_issues" do
      repo_id = params[:repository_id]
      return 400 if repo_id.nil?

      repo = Repository.find_by(id: repo_id)
      return 404 if repo.nil?

      issues = repo.issues.where(state: "open").order("issues.id DESC").take(5)

      [{
        issues: issues.each_with_index.map do |issue, index|
          min_score = 1 - 0.1 * (index + 1)
          score = min_score + rand * 0.1

          { issue_id: issue.id, score: score }
        end,
      }].to_json
    end

    # home_page_globe
    #
    # Returns: A big 'ol JSON file. Check out the fixture.
    get "/features/daily_global_pr" do
      if params["page"].to_i == 1 || params["page"].blank?
        File.read("test/fixtures/site/home-page-globe-munger-response-page-1.json")
      elsif params["page"].to_i == 2
        File.read("test/fixtures/site/home-page-globe-munger-response-page-2.json")
      else
        "[]"
      end
    end

    # trending_developers
    #
    # Response:
    #
    # [ {
    #   user_id: 123, // database ID of a valid User
    #   score: 0.5,   // random score between 0.0 and 1.0
    #   profile_location: "Nowhere", // hardcoded nonsense
    #   most_popular_repo_id: 456, // database ID of the most recently created
    #                              // Repository owned by this User, if any.
    #                              // nil if absent
    # } ]

    get "/features/trending_developers/:period" do
      unless Munger::Client::TRENDING_PERIOD_MAPPING.has_key?(params[:period].to_sym)
        return 400
      end

      count = Integer(params.fetch(:per_page, 5))
      users = User.where.not(id: User.ghost.id).order("id DESC").take(count)

      users.map do |user|
        repo = user.public_repositories.order("id DESC").take

        {
          user_id: user.id,
          score: rand,
          profile_location: "Nowhere",
          most_popular_repo_id: repo&.id,
        }
      end.to_json
    end

    # trending_repositories
    #
    # Response:
    #
    # [ {
    #   repository_id: 123, // database ID of a public Repository
    #   primary_language_id: 456, // database ID of the repo's LanguageName, or nil
    #   primary_language_name: "Ruby", // name of the repo's LanguageName, or nil
    #   spoken_language_code: "en", // spoken language code if one was requested
    #                               // with a ?spoken_language_code parameter,
    #                               // "unknown" otherwise
    #   spoken_language_confidence: 0.99, // 0.99 if a spoken language code was
    #                                     // requested; randomly chosen value
    #                                     // over the threshold otherwise
    #   score: 0.5, // random score between 0.0 and 1.0
    # } ]

    get "/features/trending_repositories/:period" do
      unless Munger::Client::TRENDING_PERIOD_MAPPING.has_key?(params[:period].to_sym)
        return 400
      end

      count = Integer(params.fetch(:per_page, 5))
      repos = Repository.includes(:primary_language, :open_graph_image).where(public: true)

      if params.has_key?(:primary_language_id)
        repos = repos.where(primary_language_name_id: params[:primary_language_id])
      end
      repos = repos.order("id DESC").take(count)

      spoken_language_code = params.fetch(:spoken_language_code,
        ExploreFeed::Trending::Repository::UNKNOWN_SPOKEN_LANGUAGE_CODE)
      confidence_min = ExploreFeed::Trending::Repository::MINIMUM_SPOKEN_LANGUAGE_CONFIDENCE
      spoken_language_confidence = params.has_key?(:spoken_language_code) ? 0.99 : nil

      repos.map do |repo|
        {
          repository_id: repo.id,
          primary_language_id: repo.primary_language&.id,
          primary_language_name: repo.primary_language&.name,
          spoken_language_code: spoken_language_code,
          spoken_language_confidence:
            spoken_language_confidence || confidence_min + rand * (1.0 - confidence_min),
          score: rand,
        }
      end.to_json
    end

    # topic_recommendations
    #
    # Response:
    #
    # { recommendations: [ {
    #     id: 123, // valid database ID of a Topic
    #     name: "Cheese", // the Topic's name
    #     score: 0.5  // a random number between 0.0 and 1.0
    # } ] }

    get "/features/topic_recommendations/:user_id" do
      unless User.exists?(id: params[:user_id])
        return 404
      end

      topics = Topic.order("id DESC").take(5)

      {
        recommendations: topics.map do |topic|
          {
            id: topic.id,
            name: topic.name,
            score: rand,
          }
        end,
      }.to_json
    end

    # related_topics
    #
    # Response:
    #
    # [
    #   {
    #     "additional_data": "none",
    #     "dimension": "minecraft",
    #     "dimension_name": "topic",
    #     "metric": 885.6126545151133,
    #     "name": "relatedtopics_topic_score",
    #     "subject_id": "mod",
    #     "subject_name": "topic",
    #     "version": 1,
    #     "window_timestamp": 1598262834,
    #     "window_type": "snapshot"
    #   },
    #   ...
    # ]
    get "/features/related_topics" do
      topic_names = Topic.order("id DESC").limit(5).pluck(:name)

      topic_names.map do |topic_name|
        {
          additional_data: "none",
          dimension: topic_name,
          dimension_name: "topic",
          metric: rand,
          name: "relatedtopics_topic_score",
          subject_id: "mod",
          subject_name: "topic",
          version: 1,
          window_timestamp: 1598254694,
          window_type: "snapshot"
        }
      end.to_json
    end

    # unsubscribe_suggestion
    #
    # Response:
    #
    # {
    #   snapshot_date: "2020-04-17",
    #   user_id: 1,
    #   algorithm_version: "0.0.1",
    #   candidates: [
    #     {
    #        repository_id: 1,
    #        score: 0.98
    #      }
    #   ]
    # }

    get "/features/unsubscribe_suggestions/:user_id" do
      user = User.find_by(id: params[:user_id])
      return 404 unless user

      # Use the users subscription list to act as a list for the fake munger results
      subscribed_repositories = GitHub.newsies.subscribed_repositories(user, set: :subscribed, page: 1, per_page: 10)

      # Munger does not have any results for the user
      # ref: https://github.com/github/ml-notifications/issues/9#issuecomment-582054236
      return 404 unless subscribed_repositories.present?

      {
        snapshot_date: Time.now.strftime("%Y-%m-%d"),
        user_id: user.id,
        algorithm_version: "0.0.1",
        candidates: subscribed_repositories.value.map.with_index do |repo, index|
          {
            repository_id: repo.id,
            score: "%.2f" % (index.to_f / 10.to_f)
          }
        end.reverse
      }.to_json
    end

    # navigation_destinations
    #
    # Response:
    # {
    #   "user_id": 1,
    #   "navigation_destinations": [
    #     {
    #     "generated_at": 1598227200,
    #     "last_visited_at": 1597900072,
    #     "target_id": 191051391,
    #     "target_name": "redwoodjs/redwood",
    #     "target_type": "Repository",
    #     "visit_count": 3
    #     },
    #     {
    #     "generated_at": 1598227200,
    #     "last_visited_at": 1597302325,
    #     "target_id": null,
    #     "target_name": "chatterbugapp/8",
    #     "target_type": "Project",
    #     "visit_count": 1
    #     }
    #   ]
    # }

    get "/features/user_navigation_destinations/:user_id" do
      { navigation_destinations: [] }.to_json
    end

    # flamingo_adoption_repository (Actions adoption)
    #
    # Response
    # {
    #   "created_at": "9/21/2021",
    #   "entity_id": 369793942,
    #   "label": "engaged",
    #   "model_name": "actions-propensity,
    #   "model_version": 1,
    #   "propensity_score": 1,
    #   "uuid": "3d90b194-5bf2-11ec-87cf-acde48001122"
    # }
    get "/features/actions_propensity_repository/:repo_id" do
      return 404 unless params[:repo_id].to_i.positive?

      {
        created_at: Time.now.strftime("%d/%m/%Y"),
        entity_id: params[:repo_id],
        label: "engaged",
        model_name: "actions-propensity",
        model_version: rand(2),
        propensity_score: rand(3),
        uuid: "uuid-#{params[:repo_id]}"
      }.to_json
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  Munger::FakeServer.set(:bind, "127.0.0.1")
  Munger::FakeServer.set(:port, ARGV[1]) if ARGV[1]
  Munger::FakeServer.run!
end
