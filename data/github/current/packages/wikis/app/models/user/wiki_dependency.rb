# typed: true
# frozen_string_literal: true

module User::WikiDependency
  def can_edit_wikis?
    authorization = ContentAuthorizer.authorize(self, :wiki, :edit)
    authorization.authorized?
  end
end
