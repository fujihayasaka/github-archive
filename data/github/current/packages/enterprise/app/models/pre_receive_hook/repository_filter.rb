# typed: true
# frozen_string_literal: true

class PreReceiveHook::RepositoryFilter

  def initialize(viewer, string)
    @viewer = viewer
    @string  = string ? string.dup : ""
  end

  def results
    if @string.empty?
      {}
    else
      do_search
    end
  end

  def build_query
    @owner_name, slash, @repo_name = @string.partition("/")
    query = "fork:true "
    if slash.empty?
      query + "#{@owner_name}"
    elsif @repo_name.empty?
      query + "user:#{@owner_name}"
    else
      query + "#{@repo_name} user:#{@owner_name}"
    end
  end

  private

  def do_search

    query = ::Search::Queries::RepoQuery.new \
      current_user: @viewer,
      phrase: build_query,
      page: 1,
      per_page: 15,
      normalizer: nil

    query.execute
  end

end
