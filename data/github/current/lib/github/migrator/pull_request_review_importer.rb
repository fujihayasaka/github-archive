# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class PullRequestReviewImporter < GitHub::Migrator::Importer

      def import(attributes, options = {})
        review = PullRequestReview.new do |review|
          pull_request = model_from_source_url!(attributes["pull_request"])
          review.pull_request = pull_request
          review.user = user_or_fallback(attributes["user"])
          review.body = attributes["body"]
          review.formatter = attributes["formatter"]
          review.head_sha = attributes["head_sha"]
          review.state = attributes["state"]
          review.created_at = attributes["created_at"]
          review.submitted_at = attributes["submitted_at"]
        end

        import_model(review)
      end
    end
  end
end
