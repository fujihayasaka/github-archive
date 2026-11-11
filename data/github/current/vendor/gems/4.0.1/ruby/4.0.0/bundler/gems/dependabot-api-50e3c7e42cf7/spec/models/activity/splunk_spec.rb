# frozen_string_literal: true

require "rails_helper"

RSpec.describe Activity::Splunk do
  describe "::all_activity_table_url" do
    it "builds a url for the correct host with a query string" do
      expect(described_class.all_activity_table_url).to include("splunk.githubapp.com", "?")
    end

    it "defaults the search to the last 24 hours" do
      expect(described_class.all_activity_table_url).to include("earliest=-24h&latest=now")
    end

    it "url encodes a splunk query for the activity log" do
      expect(described_class.all_activity_table_url).to include(
        "q=index%3D#{index_name}+app%3Ddependabot-api+activity_log_event%3D%2A"
      )
    end

    it "url encodes a splunk table function" do
      expect(described_class.all_activity_table_url).to include(
        "%7C+table+activity_log_event"
      )
    end
  end

  context "with an account" do
    let(:account) { FactoryBot.create(:account) }

    let(:splunk) { described_class.new(account: account) }

    it "filters the query by the account's github_id" do
      expect(splunk.table_url).to include(
        "q=index%3D#{index_name}" \
        "+app%3Ddependabot-api+activity_log_event%3D%2A" \
        "+gh.owner.id%3D#{account.github_id}"
      )
    end
  end

  context "with a repository" do
    let(:repo) { FactoryBot.create(:repo) }

    let(:splunk) { described_class.new(repo: repo) }

    it "filters the query by the repository's github_id" do
      expect(splunk.table_url).to include(
        "q=index%3D#{index_name}" \
        "+app%3Ddependabot-api+activity_log_event%3D%2A" \
        "+gh.repo.id%3D#{repo.github_id}"
      )
    end
  end

  context "with an update config" do
    let(:update_config) { FactoryBot.create(:update_config) }

    let(:splunk) { described_class.new(update_config: update_config) }

    it "filters the query by the update config's id" do
      expect(splunk.table_url).to include(
        "q=index%3D#{index_name}+app%3Ddependabot-api+activity_log_event%3D%2A+" \
        "gh.dependabot_api.update_config.id%3D#{update_config.id}"
      )
    end
  end

  context "with an update job" do
    let(:update_job) { FactoryBot.create(:update_job) }

    let(:splunk) { described_class.new(update_job: update_job) }

    it "filters the query by the update job's id" do
      expect(splunk.table_url).to include(
        "q=index%3D#{index_name(update_job)}+app%3Ddependabot-api+activity_log_event%3D%2A+" \
        "gh.dependabot_api.update_job.id%3D#{update_job.id}"
      )
    end
  end

  context "with a pull request" do
    let(:pull_request) { FactoryBot.create(:pull_request) }

    let(:splunk) { described_class.new(pull_request: pull_request) }

    it "filters the query by the pull request's id" do
      expect(splunk.table_url).to include(
        "q=index%3D#{index_name}+app%3Ddependabot-api+activity_log_event%3D%2A+" \
        "gh.dependabot_api.pull_request.id%3D#{pull_request.id}"
      )
    end
  end

  describe "#api_logs_url" do
    it "builds a URL relative to the update job's execution" do
      update_job = FactoryBot.create(:update_job, :processed)
      splunk = described_class.new(update_job: update_job)

      expect(splunk.api_logs_url).to include(CGI.escape("index=#{index_name(update_job)}"))
      expect(splunk.api_logs_url).to include(update_job.id.to_s)

      earliest = (update_job.created_at - described_class::PADDING).to_i
      expect(splunk.api_logs_url).to include("earliest=#{earliest}")

      latest = (update_job.last_transition.created_at + described_class::PADDING).to_i
      expect(splunk.api_logs_url).to include("latest=#{latest}")
    end
  end

  describe "monolith_logs_url" do
    it "builds a URL relative to the update job's execution" do
      update_job = FactoryBot.create(:update_job, :processed)
      splunk = described_class.new(update_job: update_job)

      expect(splunk.monolith_logs_url).to include(CGI.escape("index=rails"))
      expect(splunk.monolith_logs_url).to include(update_job.update_config.repo.github_id.to_s)
      expect(splunk.monolith_logs_url).to include(
        CGI.escape("gh.actor.id=#{Dependabot::Application.github_dependabot_user_id}")
      )

      earliest = (update_job.created_at - described_class::PADDING).to_i
      expect(splunk.monolith_logs_url).to include("earliest=#{earliest}")

      latest = (update_job.last_transition.created_at + described_class::PADDING).to_i
      expect(splunk.monolith_logs_url).to include("latest=#{latest}")
    end
  end

  def index_name(update_job = nil)
    return "dependabot" if update_job.blank? || update_job.updated_at.blank?

    if update_job.updated_at < described_class::LEGACY_INDEX_EOL
      "catchall"
    else
      "dependabot"
    end
  end
end
