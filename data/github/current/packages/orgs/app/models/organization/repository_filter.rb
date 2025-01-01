# typed: true
# frozen_string_literal: true

require "set"

class Organization::RepositoryFilter
  include Scientist

  MAX_SEARCHABLE_REPOS = 2000

  def self.too_many_repos?(repositories_count)
    repositories_count >= MAX_SEARCHABLE_REPOS
  end

  def initialize(organization, viewer:, phrase: nil, scope: nil, type: nil)
    @organization, @viewer = organization, viewer
    @string = phrase ? phrase.dup : "".dup
    @filters = Set.new
    @repositories_scope = scope
    @type = type
    extract_filters!
  end

  def results
    return [] if only_public? && only_private?
    return [] if only_sources? && only_forks?
    return [] if only_private? && !@organization.direct_or_team_member?(@viewer)
    return [] if self.class.too_many_repos?(repositories_scope.size)

    scope = repositories_scope
    scope = scope.private_scope if only_private?
    scope = scope.public_scope if only_public?
    scope = scope.joins(:mirror) if only_mirrors?
    scope = scope.forks if only_forks?
    scope = scope.where(parent_id: nil) if only_sources?

    if @string.present?
      like = "%#{ActiveRecord::Base.sanitize_sql_like(@string.downcase)}%"

      sql = <<-SQL
        repositories.name LIKE ?
        OR
        repositories.owner_id IN (?)
      SQL

      owner_ids = User.where(id: scope.distinct.pluck(:owner_id)).where("users.login LIKE ?", like).ids - [@organization.id]
      scope = scope.where(sql, like, owner_ids)
    end

    scope.order("repositories.pushed_at DESC")
  end

  def only_public?
    @type == "public" || @filters.include?("public")
  end

  def only_private?
    @type == "private" || @filters.include?("private")
  end

  def only_forks?
    @type == "fork" || @filters.include?("forks")
  end

  def only_sources?
    @type == "source" || @filters.include?("sources")
  end

  def only_mirrors?
    return false unless GitHub.mirrors_enabled?
    @type == "mirror" || @filters.include?("mirror")
  end

  private

  def repositories_scope
    @repositories_scope ||= @organization.visible_repositories_for(@viewer)
  end

  def extract_filters!
    @string.gsub!(/only:(public|private|forks|sources|mirror)/) do |_|
      @filters << $1
      "" # remove the filter from the string
    end

    @string.strip!
  end
end
