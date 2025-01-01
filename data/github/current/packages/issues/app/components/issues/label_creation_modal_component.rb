# typed: strict
# frozen_string_literal: true

module Issues
  class LabelCreationModalComponent < ApplicationComponent
    extend T::Sig

    sig { params(labelable: T.any(Issue, Discussion), repository: Repository).void }
    def initialize(labelable:, repository:)
      @labelable  = T.let(labelable, T.any(Issue, Discussion))
      @repository = T.let(repository, Repository)
    end

    private

    sig { returns(T.any(Issue, Discussion)) }
    attr_reader :labelable

    sig { returns(Repository) }
    attr_reader :repository

    sig { returns(T.nilable(Integer)) }
    def issue_id
      return if labelable.is_a?(Discussion)
      labelable.id
    end

    sig { returns(Symbol) }
    def list_item_kind
      labelable.is_a?(Discussion) ? :discussion : :issue
    end

    sig { returns(String) }
    def context
      if labelable.is_a?(Discussion)
        "discussion sidebar"
      elsif labelable.pull_request?
        "pull request sidebar"
      else
        "issue sidebar"
      end
    end

    sig { returns(String) }
    def form_path
      labels_path(
        repository.owner_display_login,
        repository.name,
        return_label_list_item: list_item_kind,
      )
    end
  end
end
