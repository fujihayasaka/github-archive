# typed: true
# frozen_string_literal: true

class ImportableCommitComment < CommitComment
  include Importable

  def type
    "CommitComment"
  end
end
