# typed: true
# frozen_string_literal: true

class PullRequestConflict < ApplicationRecord::Domain::IssuesPullRequests
  belongs_to :pull_request

  enum :conflict_type, [:merge_conflict, :rebase_conflict, :merge_queue_conflict]

  before_create :set_repository_id # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  def data
    return nil if info.nil?
    @json ||= JSON.parse(info)
  end

  def filenames
    return nil if data.nil?
    @filenames ||= data["conflicted_files"].keys.map { |f| CGI.unescape(f) }
  end

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def resolvable?
    @resolvable ||= !max_files_exceeded? && regular_conflicts_only? && all_files_within_limits? && all_files_text?
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  def max_files_exceeded?
    return false if data.nil?
    @max_files_exceeded ||= !!data["more_conflicted_files"]
  end

  def regular_conflicts_only?
    return false if data.nil?
    !data["conflicted_files"].values.any? { |v| v["type"] != "regular_conflict" }
  end

  def all_files_within_limits?
    return false if data.nil?
    !data["conflicted_files"].values.any? do |v|
      (v["base"] && v["base"]["file_size"] && v["base"]["file_size"].to_i > 1.megabyte) ||
      (v["head"] && v["head"]["file_size"] && v["head"]["file_size"].to_i > 1.megabyte)
    end
  end

  def all_files_text?
    return false if data.nil?
    !data["conflicted_files"].values.any? do |v|
      (v["base"] && v["base"]["binary"]) || (v["head"] && v["head"]["binary"])
    end
  end

  def file_info(filename)
    data["conflicted_files"][CGI.escape(filename).force_encoding(::Encoding::UTF_8)]
  end

  private

  def set_repository_id
    self.repository_id = self.pull_request&.repository_id
  end
end
