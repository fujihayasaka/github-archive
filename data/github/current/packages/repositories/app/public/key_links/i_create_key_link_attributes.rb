# typed: strict
# frozen_string_literal: true

module KeyLinks
  ICreateKeyLinkAttributes = T.type_alias do
    {
      key_prefix: String,
      url_template: String,
      owner: ::Repository,
      is_alphanumeric: T.nilable(T::Boolean)
    }
  end
end
