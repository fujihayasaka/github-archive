# typed: true
# frozen_string_literal: true

class Release::SearchTags
  extend T::Sig

  # This regex matches any number of dot seperated integers, preceded by an optional v or V
  # it is similar to a pep 440 final release version
  # e.g. v1.0, v1, v2.0.0.1, v3.0.0, etc
  VERSION_REGEX = /\A[vV]?(\d*)(\.(\d*))*\z/.freeze

  # This regex matches the default suffix added by `git describe`
  #
  # > it suffixes the tag name with the number of additional commits
  # > on top of the tagged object and the abbreviated object name
  # of the most recent commit.
  #
  # https://git-scm.com/docs/git-describe
  GIT_DESCRIBE_SUFFIX_REGEX = /(-[^-]+){2}\z/

  MAX_TAGS_TO_SEARCH = 100
  TAG_SEARCH_TIMEOUT_SECONDS = 6

  sig { params(release: Release).void }
  def initialize(release)
    @release = release
    @repo = release.repository
  end

  # If the release.exposed_tag_name is in valid semver syntax, examine each tag reachable from @release.current_target
  # in reverse order until one has a valid version identifier
  sig { returns(T.nilable(String)) }
  def find_previous_version_tag
    return nil unless @release.exposed_tag_name&.match?(VERSION_REGEX)
    tag_names = get_previous_tags(@release.current_target)
    tags_searched = tag_names.size
    version_tag = T.let(nil, T.nilable(String))
    version_tag = find_version_match(tag_names)

    # we need a hard timeout here because calls to git describe can be extremely slow for certain repos with huge numbers of refs
    # we cannot catch all of these cases up front, so we timeout here as a last resort
    # all operations in the timeout block are read-only and safe to interrupt
    begin
      GitHub::Timer.timeout(TAG_SEARCH_TIMEOUT_SECONDS) do
        until version_tag || !tag_names.present? || tags_searched >= MAX_TAGS_TO_SEARCH do
          tag_names = get_previous_tags(tag_names.first)
          version_tag = find_version_match(tag_names)
          tags_searched += tag_names.size
        end
      end
    rescue Timeout::Error => e
      Failbot.report(e)
      return nil
    end

    version_tag
  end

  # Given a tag name, gets the closest previous reachable tag,
  # and any other tags referencing the same commit as that tag
  sig { params(start_tag_name: T.nilable(String)).returns(T::Array[T.nilable(String)]) }
  def get_previous_tags(start_tag_name)
    begin
      start_tag = @repo.tags.find(start_tag_name)
      previous_tag_name = @repo.rpc.describe("#{start_tag_name}^1")
      previous_tag_name.gsub!(GIT_DESCRIBE_SUFFIX_REGEX, "")
      previous_tag = @repo.tags.find(previous_tag_name)
      # limit results to only valid tags
      return [] unless previous_tag.present?
    rescue GitRPC::ObjectMissing
      return []
    end

    # get all tags referencing the same commit as the previous tag
    tag_names_containing_commit = @repo.rpc.tag_contains(previous_tag.target.oid)
    tags_containing_commit = @repo.tags.find_all(Git::Ref::Collection.qualify_tag_names(tag_names_containing_commit))
    tags_containing_commit.select do |tag|
      tag.present? && tag.target.oid == previous_tag.target.oid
    end.map { |tag| tag.name }
  end

  sig { params(tag_names: T::Array[T.nilable(String)]).returns(T.nilable(String)) }
  def find_version_match(tag_names)
    tag_names.find { |tag_name| tag_name&.match?(VERSION_REGEX) }
  end
end
