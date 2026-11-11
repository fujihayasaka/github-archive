# typed: strict
# frozen_string_literal: true

module Repositories
  class TitleComponent < ApplicationComponent
    extend T::Helpers

    include RepositoriesHelper
    include StacksHelper
    include AvatarHelper

    sig { params(repository: Repository, title_class: T.nilable(String)).void }
    def initialize(repository:, title_class: "")
      @repository = repository
      @title_class = title_class
    end
  end
end
