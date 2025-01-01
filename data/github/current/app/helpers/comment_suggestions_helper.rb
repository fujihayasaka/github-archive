# typed: true
# frozen_string_literal: true

module CommentSuggestionsHelper
  def suggestions_params(repository, subject)
    if subject
      subject_type = subject.class.name.underscore
      subject_id = subject.suggestion_id if subject.respond_to?(:suggestion_id)
    end
    {
      user_id: repository.owner.display_login,
      repository: repository.name,
      subject_type: subject_type,
      subject_id: subject_id
    }
  end

  # Returns params suitable for ajax requests to get the issue autocomplete suggestions for a repo
  # This is used for our comment suggester, with the `suggestions_path` method
  def issue_suggestions_params(repository, subject)
    suggestions_params(repository, subject).merge(issue_suggester: 1)
  end

  # Returns params suitable for ajax requests to get the autocomplete suggestions for a repo
  # (i.e., members of teams with access to the repo, users that have committed to the repo.).
  # This is used for our comment suggester, with the `suggestions_path` method
  def mention_suggestions_params(repository, subject)
    suggestions_params(repository, subject).merge(mention_suggester: 1)
  end
end
