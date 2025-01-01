# typed: true
# frozen_string_literal: true

class RepositoryWiki::Comparison
  attr_reader :wiki, :repository, :page, :new_revision, :old_revision

  NEW_REVISION_REGEX = /\A[0-9a-fA-F]+\z/
  OLD_REVISION_REGEX = /\A[0-9a-fA-F]+\^?\z/

  def initialize(wiki, page, versions)
    @wiki         = wiki
    @repository   = wiki.repository
    @page         = page
    @versions     = versions

    # There should always be a newer version, the older version is optional
    # and will default to newer's parent.
    @new_revision, @old_revision = @versions.first(2)
  end

  def valid?
    valid_shas? && valid_objects?
  end

  def valid_shas?
    (@new_revision&.is_a?(String) || @old_revision&.is_a?(String)) &&
      (@new_revision.nil? || !!(@new_revision =~ NEW_REVISION_REGEX)) &&
      (@old_revision.nil? || !!(@old_revision =~ OLD_REVISION_REGEX))
  end

  def valid_objects?
    begin
      newer_commit = @wiki.commits.find(@wiki.spokes_api.resolve_object(object_name: @new_revision)) if @new_revision
      older_commit = @wiki.commits.find(@wiki.spokes_api.resolve_object(object_name: @old_revision)) if @old_revision
      true
    rescue GitRPC::ObjectMissing
      false
    end
  end

  def diffs
    @page ? @page.diff(@old_revision, @new_revision) : @wiki.diff(@old_revision, @new_revision)
  end

  def comparable?
    @old_revision != @new_revision
  end

  def missing_commits?
    diffs && diffs.missing_commits?
  end

  def diff_available?
    diffs && diffs.available?
  end

  def revertable_by?(actor)
    comparable? && @old_revision && @repository.wiki_writable_by?(actor)
  end

  def tree_diff
    @wiki.rpc.read_tree_diff(@old_revision, @new_revision)
  end
end
