# typed: true
# frozen_string_literal: true

module Repository::Sequence
  extend T::Helpers

  requires_ancestor { Repository }

  # Internal: Ensures a sequence is created for the repository.
  #
  # Returns nothing.
  def create_sequence
    ::Sequence.create(self)
    true
  end

  def sequence_type
    RepositorySequence
  end

  def fix_duplicate_sequence_for_issue(number:)
    duplicate_issues = self.issues.where(number:).to_a.drop(1)

    raise RuntimeError, "Too many duplicate issues (#{duplicate_issues.size}) for repo #{self.id} issue \##{number}" if duplicate_issues.size >= 5

    duplicate_issues.each do |issue|
      issue.update!(number: Sequence.next(issue.repository))
    end
  end
end
