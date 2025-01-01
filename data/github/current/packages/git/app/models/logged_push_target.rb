# typed: true
# frozen_string_literal: true

# Public: methods for parsing and representing a target from a repository's pushlog.
#
# Examples
#
#   target = LoggedPushTarget.new("refs/heads/master", "fab0d81b3c1bf4ee94b58cc3243982fb400a314b", "f4e6f19cf35e0c68e86fdacd1e2f17890c972be5")
#   => #<PushTarget @ref="refs/heads/master", @before="fab0d81b3c1bf4ee94b58cc3243982fb400a314b", @after="f4e6f19cf35e0c68e86fdacd1e2f17890c972be5">
#
#   target = LoggedPushTarget.parse_reflog_line("  refs/heads/master fab0d81b3c1bf4ee94b58cc3243982fb400a314b f4e6f19cf35e0c68e86fdacd1e2f17890c972be5\n")
#   => #<PushTarget @ref="refs/heads/master", @before="fab0d81b3c1bf4ee94b58cc3243982fb400a314b", @after="f4e6f19cf35e0c68e86fdacd1e2f17890c972be5">
#
#   target.ref
#   => "refs/heads/master"
#
#   target.before
#   => "fab0d81b3c1bf4ee94b58cc3243982fb400a314b"
#
#   target.after
#   => "f4e6f19cf35e0c68e86fdacd1e2f17890c972be5"
class LoggedPushTarget
  # Public: Returns the String name of the pushed ref.
  attr_reader :ref

  # Public: Returns the String OID of the ref's target before the push.
  attr_reader :before

  # Public: Returns the String OID of the ref's target after the push.
  attr_reader :after

  # Public: Initialize a LoggedPushTarget
  #
  # ref        - the String name of the pushed ref.
  # before_oid - the String OID of the ref before the push.
  # after_oid  - the String OID of the ref after the push.
  def initialize(ref, before_oid, after_oid)
    @ref     = ref
    @before  = before_oid
    @after   = after_oid

    @created = before_oid == GitHub::NULL_OID
    @deleted = after_oid  == GitHub::NULL_OID
  end

  # Public: Parse a secondary push target data from a line of squashed pushlog output.
  #
  # line - the String line of output from git-push-log.
  #
  # Examples
  #
  #   LoggedPushTarget.parse_reflog_line("  refs/heads/master fab0d81b3c1bf4ee94b58cc3243982fb400a314b f4e6f19cf35e0c68e86fdacd1e2f17890c972be5")
  #   => #<PushTarget @ref="refs/heads/master", @before="fab0d81b3c1bf4ee94b58cc3243982fb400a314b", @after="f4e6f19cf35e0c68e86fdacd1e2f17890c972be5">
  #
  # Returns a LoggedPushTarget for the pushlog entry.
  def self.parse_reflog_line(line)
    ref, before_oid, after_oid = line.strip.split(" ")
    new(ref, before_oid, after_oid)
  end

  # Public: Whether the push created this target ref.
  #
  # Examples
  #
  #   target.before
  #   => "0000000000000000000000000000000000000000"
  #
  #   target.created?
  #   => true
  #
  # Returns a Boolean.
  def created?
    @created
  end

  # Public: Whether the push deleted this target ref.
  #
  # Examples
  #
  #   target.after
  #   => "0000000000000000000000000000000000000000"
  #
  #   target.deleted?
  #   => true
  #
  # Returns a Boolean.
  def deleted?
    @deleted
  end

  # Public: Get the target ref's abbreviated commit OID before the push.
  #
  # Examples
  #
  #   target.short_before
  #   => "fab0d81"
  #
  # Returns the before OID String in a more human-readable size.
  def short_before
    before.to_s[0, 7]
  end

  # Public: Get the target ref's abbreviated commit OID after the push.
  #
  # Examples
  #
  #   target.short_after
  #   => "f4e6f19"
  #
  # Returns the after OID String in a more human-readable size.
  def short_after
    after.to_s[0, 7]
  end

  # Public: Get the String before -> after commit range that can be used to
  #         compare the tree's before and after state.
  #
  # Examples
  #
  #   target.commit_range
  #   => "fab0d81b3c1bf4ee94b58cc3243982fb400a314b...f4e6f19cf35e0c68e86fdacd1e2f17890c972be5"
  #
  # Returns the String compare range.
  def commit_range
    "#{before}...#{after}"
  end

  # Public: Get a more human-readable version of the commit range String.
  #
  # Examples
  #
  #   target.short_commit_range
  #   => "fab0d81...f4e6f19"
  #
  # Returns the String compare range.
  def short_commit_range
    "#{short_before}...#{short_after}"
  end
end
