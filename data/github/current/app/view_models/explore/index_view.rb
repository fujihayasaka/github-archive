# typed: true
# frozen_string_literal: true

class Explore::IndexView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :repos_by_nwo

  # Public: Returns a GraphQL Repository based on the given name-with-owner.
  def repo_for(name_with_owner)
    if repos_by_nwo && name_with_owner.to_s.include?("/")
      repos_by_nwo[name_with_owner]
    end
  end
end
