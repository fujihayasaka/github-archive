# typed: true
# frozen_string_literal: true

module Stafftools
  class BulkDmcaTakedown::Notice
    include ActiveModel::Model

    attr_accessor :notice_text, :public_url
    validates_presence_of :public_url
    validates_presence_of :notice_text
    validates :public_url, format: { with: GitRepositoryAccess::TAKEDOWN_URL_FORMAT, message: "is invalid" }
    validate :must_contain_repo_urls
    validate :number_of_repos_cannot_exceed_max

    def grouped_urls
      @grouped_urls ||= GitHub::Stafftools.group_urls_by_repo(notice_text)
    end

    def repositories
      grouped_urls.keys
    end

    def must_contain_repo_urls
      unless repositories.any?
        errors.add(:notice_text, "must contain valid repository URLs")
      end
    end

    def number_of_repos_cannot_exceed_max
      max = Stafftools::BulkDmcaTakedown::MAX_REPOS

      unless repositories.count < max
        errors.add(:notice_text, "can contain at most #{max} repositories")
      end
    end
  end
end
