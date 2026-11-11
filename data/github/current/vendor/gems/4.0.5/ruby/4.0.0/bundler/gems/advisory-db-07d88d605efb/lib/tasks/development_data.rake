# frozen_string_literal: true

namespace :db do
  desc "Populate development environment with data for testing and development"
  task development_data: [:environment, :seed] do
    AdvisoryDBDevelopmentEnvironmentSeeds.seed
  end

  desc "Generate random vulnerability predictions for an AdvisoryReview by GHSA"
  task :generate_predictions, [:ghsa_id] => [:environment] do |_task, args|
    unless Rails.env.development?
      puts "not available in #{Rails.env} environment"
      exit
    end

    if args[:ghsa_id].blank?
      puts "missing GHSA ID"
      exit
    end

    advisory_review = AdvisoryReview.find_by!(ghsa_id: args[:ghsa_id])
    AdvisoryDBDevelopmentEnvironmentSeeds.generate_predictions(advisory_review)
  end
end

module AdvisoryDBDevelopmentEnvironmentSeeds
  def self.seed
    return unless Rails.env.development?

    ::GitHub::Telemetry::Logs.logger.info("Seeding database with development data")
    create_advisory_reviews
    create_cve_requests
  end

  def self.create(*args)
    FactoryBot.create(*args)
  rescue ActiveRecord::RecordNotUnique => error
    ::GitHub::Telemetry::Logs.logger.debug(
      "Error creating seed data",
      exception: error,
      "gh.advisory_inbox.seed_args": args,
    )
  end

  def self.create_advisory_reviews
    ::GitHub::Telemetry::Logs.logger.info("Seeding database with development data: AdvisoryReviews")
    # One AdvisoryReview for each of the basic states
    create :advisory_review, :open,                             summary: "Basic open Review"
    create :advisory_review, :in_review,                        summary: "Basic in-review Review"
    create :advisory_review, :closed,                           summary: "Basic closed Review"
    create :advisory_review, :rejected,                         summary: "Basic rejected Review"
    create :advisory_review, :curation_state_published,         summary: "Basic accepted Review"
    create :advisory_review, :curation_state_ready_to_publish,  summary: "Basic ready to publish Review"
    create :advisory_review, :curation_state_ready_to_withdraw, summary: "Basic ready to withdraw Review"
    create :advisory_review, :curation_state_withdrawn,         summary: "Basic withdrawn Review"
  end

  def self.create_cve_requests
    ::GitHub::Telemetry::Logs.logger.info("Seeding database with development data: CVEReviews")
    # CVE Reviews for state open
    create :undecided_cve_review,    cve_request_title: "Open and undecided"
    create :assigned_cve_review,     cve_request_title: "Open and decision:assigned"
    create :not_assigned_cve_review, cve_request_title: "Open and decision:not_assigned"
    # For state notified
    create :assigned_cve_review,     :notified, :all_fields_populated, cve_request_title: "Notified and decision:assigned"
    create :not_assigned_cve_review, :notified, cve_request_title: "Notified and decision:not_assigned"
    # For state submitted
    create :assigned_cve_review,     :submitted, :all_fields_populated, cve_request_title: "Submitted"
  end

  def self.generate_predictions(advisory_review)
    rand(2..5).times do
      FactoryBot.create(:vulnerability_prediction,
        advisory_review: advisory_review)
    end
  end
end
