# typed: false
# frozen_string_literal: true

module Repository::UserRankedDependency
  extend ActiveSupport::Concern
  include UserRanked::Scope

  class_methods do
    # Public: Get cached repositories a user has contributed to. See
    # User.repositories_contributed_to docs for more info on ranking. Unlike
    # self.ranked_for, this returns an Array instead of a scope.
    #
    # user - User to calculate ranked repositories for.
    # since - DateTime (optional). Defaults to 1 year ago.
    #
    # Returns an array of Repositories.
    def eager_ranked_for(user, since: nil)
      since ||= 1.year.ago

      ids = UserRanked::Cache.fetch_ranked_ids(name, user, { since: since.strftime("%m-%Y") }) do
        compute_ranked_ids(user: user, since: since)
      end

      return [] if ids.empty?
      Repository.active.where(id: ids).order(Arel.sql("FIELD(#{table_name}.id, #{ids.reverse.join(', ')}) DESC")).order(:id).to_a
    end

    def compute_ranked_ids(user:, since: nil)
      since ||= 1.year.ago

      user.ranked_contributed_repositories(
        include_issue_comments: true,
        since: since.at_beginning_of_month,
      ).keys.map(&:id)
    end
  end
end
