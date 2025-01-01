# typed: true
# frozen_string_literal: true

require "json"

module VariantAnalysis::CodeScanningRepoLists

  class InvalidQueryList < StandardError; end
  class QueryListParseError < StandardError; end

  MRVA_TOP_REPOS_ID = 468078842 # repo id for github/mrva-top-repos (the default)

  # Use this method inside of tests only
  def self.mrva_top_repos_id
    MRVA_TOP_REPOS_ID
  end

  def self.get_repo_list(language, list_name)
    validate_language!(language)
    validate_list_name!(list_name)

    parsed_list_name, limit = parse_list_name(list_name)

    # first try to get the list from the external repository
    repos = get_list_from_repo(language, parsed_list_name)

    return nil if repos.nil?

    if !limit.nil?
      repos = repos.take(limit)
    end

    repos
  end

  private_class_method def self.get_list_from_repo(language, parsed_list_name)
    return nil if mrva_top_repos_id.nil?

    repo = ActiveRecord::Base.connected_to(role: :reading) do
      Repository.find_by(id: mrva_top_repos_id)
    end
    return nil if repo.nil?
    sha = repo.default_oid

    f = repo.blob(sha, "#{language}/#{parsed_list_name}.json")
    return nil if f.nil?

    begin
      list_data = JSON.parse(f.data)
      list_data["repositories"].map { |repo| repo["name"] }
    rescue JSON::ParserError
      raise QueryListParseError, "Invalid list contents: #{parsed_list_name}"
    end
  end

  # if the text after the final `_` of a list name is a number
  # then remove the suffix, find the list of that name, and truncate
  # it to the given number of items. If there are fewer items than
  # specified, then return the entire list.
  private_class_method def self.parse_list_name(list_name)
    if list_name.match(/\A(.*)_(\d+)\z/)
      list_name = Regexp.last_match(1)
      limit = Regexp.last_match(2).to_i
    else
      limit = nil
    end

    [list_name, limit]
  end

  private_class_method def self.validate_language!(language)
    if !CodeqlVariantAnalysis::ALLOWED_LANGUAGES.include?(language)
      raise InvalidQueryList, "Invalid language: #{language}"
    end
  end

  private_class_method def self.validate_list_name!(list_name)
    if !list_name.match(/\A\w+\z/)
      raise InvalidQueryList, "Invalid list name: #{list_name}"
    end
  end
end
