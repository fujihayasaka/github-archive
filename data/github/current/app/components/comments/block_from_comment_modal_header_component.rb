# typed: true
# frozen_string_literal: true

module Comments
  class BlockFromCommentModalHeaderComponent < ApplicationComponent
    attr_reader :from, :block

    def initialize(login:, repo:)
      @block = login
      @from = repo.owner.name
    end
  end
end
