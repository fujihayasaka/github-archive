# rubocop:disable Style/FrozenStringLiteralComment
module GitRPC::Diff::StatusMethods
  LABELS = {
    "A" => "added",
    "D" => "removed",
    "R" => "renamed",
    "C" => "copied",
    "M" => "modified",
    "T" => "changed",
    "U" => "unchanged",
    "I" => "changed",   # unknown changes due to truncated diff
  }.freeze

  # The longer version of status.
  def status_label
    LABELS[status]
  end

  def added?
    status == "A"
  end

  def removed?
    status == "D"
  end

  def renamed?
    status == "R"
  end

  def copied?
    status == "C"
  end

  def modified?
    status == "M"
  end

  def changed?
    status == "T" || status == "I"
  end

  def unchanged?
    status == "U"
  end

  alias_method :deleted?, :removed?
end
